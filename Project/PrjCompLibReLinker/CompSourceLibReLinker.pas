{ CompSourceLibReLinker.pas

 from ExplicitModelSourceInLibs.pas

Can be run as a standalone script or driven by PrjLibReLinker.pas
by adding to a common script project.

2 direct call entry points.

 1. Run on each/every SchLib that is part of Project.
 2. Run on each Sheet in SchDoc..
 3. Run on PcbDoc in project

 For each component in schLib it updates the source symbol & footprint lib names if located.
 For SchDoc (if Comp found) it undates comp link to SchLib
 For PcbDoc (if FP found) it updates source & component lib links.


 BLM

21/04/2020  DatafileLinkcount does not work in AD19
09/05/2020  0.01 from ExplicitModelSourceInLibs.pas
09/05/2020  0.02 Added PcbDoc processing. tweaked report padding/spacing..
10/05/2020  0.21 Iterate all project libraries for source, don't assume the 'hit' is in project lib
11/05/2020  0.22 Refactored some common code to fn.
12/05/2020  0.23 Setup wrapper direct calls for single doc processing or external script calls.

DBLib:
    Component is defined in the table.
    .DesignItemId is unique component identifier
    .LibReference links to the (shared) symbol entry in a SchLib

SchLib/IntLib:
    Component is defined in SchLib "symbol"  with paras & SchImpl links (models)
    .DesignItemId is not used?  (I set same as LibRef)
    .LibReference is unique symbol name

So .LibReference always points to a symbol in SchLib.

                                           when from DBLib:                                       when from IntLib:
    Component.DesignItemId;                same as existing / last part..
    Component.LibReference;                'RES_BlueRect_2Pin'         symbol                     '0R05_0805_5%_1/4W'
    Component.LibraryIdentifier;           'Database_Libs1.DBLib/Resistor'                        'STD_Resistor.IntLib'
    Component.SourceLibraryName;           'Database_Libs1.DBLib'                                 'STD_Resistor.IntLib'
    Component.SymbolReference;             same as LibRef                                         same as LibRef
...................................................................................................................}

Var
    WS        : IWorkspace;
    IntLibMan : IIntegratedLibraryManager;
    Report    : TStringList;

{..............................................................................}
Procedure GenerateModelsReport (Doc : IDocument, FileSuffix : WideString, SCount : Integer, FCount : Integer);
Var
    Prj       : IProject;
    Filepath  : WideString;
    Filename  : WideString;
    ReportDoc : IServerDocument;

Begin
    Prj := Doc.DM_Project;
    if Prj <> nil then
    begin
        Filepath := ExtractFilePath(Prj.DM_ProjectFullPath);
        Filename := Prj.DM_ProjectFileName;
    end else
    begin
        Filepath := ExtractFilePath(Doc.DM_FullPath);
        Filename := Doc.DM_Filename;
    end;

    Report.Insert(0, 'Script: CompSourceLibReLinker.pas ');
    Report.Insert(1, 'Sch & SchLib Components and Linked Model Report...');
    Report.Insert(2, '========================================================');
    Report.Insert(3, 'Project Name : ' + Filename);
    Report.Insert(4, 'Focused Doc  : ' + Doc.DM_FileName);
    Report.Insert(5, ' ');
    Report.Insert(6, ' Missing Sch Symbol Link Count : ' + IntToStr(SCount));
    Report.Insert(7, ' Missing Footprint Link Count  : ' + IntToStr(FCount) + '          search for text ---->  MISSING <---- ');
    Report.Insert(8, ' ');

    Filename := Doc.DM_FileName;
    FilePath := FilePath + 'Reports';
    if not DirectoryExists(FilePath, false) then
        DirectoryCreate(FilePath);

    Filepath := FilePath + '\' + Filename + FileSuffix;
//    Filepath := Filepath + Filename + FileSuffix;
    Report.SaveToFile(Filepath);

    ReportDoc := Client.OpenDocument('Text', Filepath);
    If ReportDoc <> Nil Then
    begin
        Client.ShowDocument(ReportDoc);
        if (ReportDoc.GetIsShown <> 0 ) then
            ReportDoc.DoFileLoad;
    end;
end;
{..............................................................................}

{..............................................................................}
Procedure SetDocumentDirty (Dummy : Boolean);
Var
    AView           : IServerDocumentView;
    AServerDocument : IServerDocument;
Begin
    If Client = Nil Then Exit;
    AView := Client.GetCurrentView;
    AServerDocument := AView.OwnerDocument;
    AServerDocument.Modified := True;
End;
{..............................................................................}

// unused.
function CheckFileInProject(Prj : IProject, FullPathName : Widestring) : boolean;
var
    I : integer;
begin
    Result := false;
    if Prj.DM_IndexOfSourceDocument(FullPathName) > -1 then Result := true;

//    for I := 0 to (Prj.DM_LogicalDocumentCount - 1) Do
//    begin
// if FullPath = Prj.DM_LogicalDocuments(I).DM_FullPath then Result := true;
//    end;
end;

function FindProjectSourceLib(Prj : IBoardProject, const DocKind : WideString, const CompName : WideString, var CompLoc : WideString) : boolean;
var
    Doc            : IDocument;
    LibIdKind      : ILibIdentifierKind;
    FoundLocation  : WideString;
    LibName        : WideString;
    InIntLib       : boolean;
    I              : integer;

begin
// TLibraryType = (eLibIntegrated, eLibSource, eLibDatafile, eLibDatabase, eLibNone, eLibQuery, eLibDesignItems);
//     LibType := eLibSource;
    Result := false;
    LibIdKind := eLibIdentifierKind_NameWithType;   // eLibIdentifierKind_Any;
    InIntLib := False;

    for I := 0 to (Prj.DM_LogicalDocumentCount - 1) do
    begin
        FoundLocation := ''; CompLoc := '';
        Doc := Prj.DM_LogicalDocuments(I);
        if Doc.DM_DocumentKind = DocKind then
        begin
//            if not Doc.DM_DocumentIsLoaded then
//                Doc.DM_LoadDocument;

            LibName := Doc.DM_FullPath;   // Doc.DM_Filename;
            if (DocKind = cDocKind_SchLib) then
                CompLoc := IntLibMan.FindComponentLibraryPath(LibIdKind, LibName, CompName);
//  this stopped working when processing whoel project?
//                CompLoc := IntLibMan.GetComponentLocation(LibName, CompName, FoundLocation);

            if (DocKind = cDocKind_PcbLib) then
//                DataFileLoc := IntLibMan.FindDatafileInStandardLibs(Component.Name, cDocKind_PcbLib, LibDoc.DM_FullPath, False {not IntLib}, FoundLocation);
                CompLoc := IntLibMan.FindDatafileEntitySourceDatafilePath(LibIdKind, LibName, CompName, cDocKind_PcbLib, InIntLib);
        end;
        if (CompLoc <> '') then
        begin
            Result := true;
            break;
        end;
    end;
end;

function LinkFPModelsWrapped (Doc : IDocument, const Fix : boolean, var SLinkCount, var FLinkCount : integer) : boolean;
var
    Prj            : IBoardProject;
    Board          : IPCB_Board;
    Component      : IPCB_Component;
    Iterator       : IPCB_BoardIterator;
    DataFileLoc    : WideString;
    FoundLibName   : WideString;
    Found          : boolean;

begin
    Result := false;
    IntLibMan := IntegratedLibraryManager;
    If IntLibMan = Nil Then Exit;
    Prj := Doc.DM_Project;
//    PcbLib := PcbServer.GetPcbLibraryByPath(Doc.DM_FullPath);
//    if PcbLib = Nil then
//        PcbLib := PcbServer.LoadPcbLibraryByPath(Doc.DM_FullPath);
    Board := PcbServer.GetPcbBoardByPath(Doc.DM_FullPath);
    if Board = Nil then
        Board := PcbServer.LoadPcbBoardByPath(Doc.DM_FullPath);

    Report := TStringList.Create;
    PCBserver.PreProcess;

    Iterator := Board.BoardIterator_Create;
    Iterator.AddFilter_ObjectSet(MkSet(eComponentObject));
    Iterator.AddFilter_LayerSet(MkSet(eTopLayer,eBottomLayer));
    Iterator.AddFilter_Method(eProcessAll);

    SLinkCount := 0; FLinkCount := 0;

    Component := Iterator.FirstPCBObject;
    While (Component <> Nil) Do
    Begin
            Found := FindProjectSourceLib(Prj, cDocKind_PcbLib, Component.Pattern, DataFileLoc);

            FoundLibName := ExtractFilename(DataFileLoc);
            if not Found then inc(FLinkCount);

            if Found then Result := true;

            if Fix and Found then
            begin
                Component.SourceFootprintLibrary := FoundLibName;
                Component.SourceComponentLibrary := FoundLibName;
                Report.Add('updated FP Comp : ' + PadRight(Component.Name.Text, 25) + '  FP : ' + PadRight(Component.Pattern, 25) +  '  lib : '  + FoundLibName);
            end else
                Report.Add('FP Comp : ' + PadRight(Component.Name.Text, 25) + '  FP : ' + PadRight(Component.Pattern, 25) +  '  FP lib : '  + Component.SourceFootprintLibrary);

        // Notify the PCB editor that the pcb object has been modified
        // PCBServer.SendMessageToRobots(Component.I_ObjectAddress, c_Broadcast, PCBM_EndModify , c_NoEventData);
        Component := Iterator.NextPCBObject;
    End;
    Board.BoardIterator_Destroy(Iterator);

    PCBServer.PostProcess;
//    PCBServer.PostProcess_Clustered;
    Client.SendMessage('PCB:Zoom', 'Action=Redraw' , 255, Client.CurrentView);

//    SetDocumentDirty(true);
    GenerateModelsReport(Doc, '-FPModels.Txt', 0, FLinkCount);
    Report.Free;
end;

// wrapped call for external proc
function LinkSchCompsWrapped(LibDoc : IDocument, Fix : boolean, var SLinkCount, var FLinkCount : integer) : boolean;
Var
    Prj             : IBoardProject;
    SchLibDoc       : ISch_Lib;
    CurrentSheet    : ISch_Document;
    Iterator        : ISch_Iterator;
    Component       : ISch_Component;
    ImplIterator    : ISch_Iterator;
    SchImpl         : ISch_Implementation;
    ModelDataFile   : ISch_ModelDatafileLink;
    FPModel         : IPcb_LibComponent;
    SourceCLibName  : WideString;
    SourceDBLibName : WideString;
    ModelDFileLoc   : WideString;
    DataFileLoc     : WideString;
    TopLevelLoc     : WideString;
    FoundLibName    : WideString;
    DBTableName     : WideString;
    FoundLibPath    : WideString;
    CompLoc         : WideString;
    SymbolRef       : WideString;
    DItemID         : WideString;
    CompLibRef      : WideString;
    CompLibID       : WideString;
    Found           : boolean;
    I               : Integer;

Begin
    Result := false;
    Prj := LibDoc.DM_Project;
    IntLibMan := IntegratedLibraryManager;
    If IntLibMan = Nil Then Exit;

//    if not LibDoc.DM_DocumentIsLoaded then
//        LibDoc.DM_LoadDocument;
    SchLibDoc := SchServer.GetSchDocumentByPath(LibDoc.DM_FullPath);
    if SchLibDoc = Nil then
        SchLibDoc := SchServer.LoadSchDocumentByPath(LibDoc.DM_FullPath);
    if SchLibDoc = Nil Then Exit;

    If SchLibDoc.ObjectID = eSchLib Then
    begin
        Iterator := SchLibDoc.SchLibIterator_Create;
        Result := true;
    end else
        Iterator := SchLibDoc.SchIterator_Create;

    Report := TStringList.Create;

    Iterator.AddFilter_ObjectSet(MkSet(eSchComponent));
    Try
        Component := Iterator.FirstSchObject;
        SLinkCount := 0;
        FLinkCount := 0;

        While Component <> Nil Do
        Begin
            CompLoc       := '';
            SymbolRef     := '';

            DItemID := Component.DesignItemID;
            CompLibRef := Component.LibReference;

            If SchLibDoc.ObjectID = eSchLib then
            begin
                Component.SetState_SourceLibraryName(ExtractFilename(SchLibDoc.DocumentName));
                // fix components extracted from dBlib into SchLib/IntLib with problems..
                //Component.DatabaseLibraryName := '';
                Component.DatabaseTableName := '';
                Component.UseDBTableName := false;
                if DItemId <> Component.LibReference then DItemId := Component.LibReference;
                Component.DesignItemId := DItemID;
            end;

            SourceCLibName  := Component.SourceLibraryName;
            SourceDBLibName := Component.DatabaseLibraryName;
            DBTableName     := Component.DatabaseTableName;

            If SchLibDoc.ObjectID = eSheet Then
                Report.Add(' Component Designator : '                 + Component.Designator.Text);
            if DItemId <> Component.DesignItemId then
                Report.Add('   DesignItemID       : ' + DItemID + ' fixed -> ' + Component.DesignItemID)
            else
                Report.Add('   DesignItemID       : ' + DItemID);
            Report.Add    ('   Source Lib Name    : ' + SourceCLibName);
            Report.Add    ('   Lib Reference      : ' + Component.LibReference);
            Report.Add    ('   Lib Symbol Ref     : ' + Component.SymbolReference);
            Report.Add    ('   Lib Identifier     : ' + Component.LibraryIdentifier);


         // think '*' causes problems placing parts in SchDoc from script.(process call without full path)
            if Component.LibraryPath = '*' then
            begin
                Component.LibraryPath := '';
                Report.Add('   LibPath was       : <*> now <blank>');
            end;

            if SourceCLibName  = '*' then Component.SetState_SourceLibraryName('');

            DItemID   := Component.DesignItemID;               // prim key for DB & we set same as LibRef for IntLib/SchLib.
            CompLibID := Component.LibraryIdentifier;

         // if SchDoc check symbols have IntLib/dBLib link
            if SchLibDoc.ObjectID = eSheet then
            begin
                Found := FindProjectSourceLib(Prj, cDocKind_SchLib, DItemID, CompLoc);

                FoundLibName := ExtractFilename(CompLoc);
                if not Found then Inc(SLinkCount);

// any found part is success!
                if Found then Result := true;

                if Fix & (Found) Then
                begin
                    Report.Add    ('   Library Path    : ' + Component.LibraryPath);
                    Component.SetState_DatabaseTableName('');
                    Component.UseDBTableName := False;
                    Component.SetState_SourceLibraryName(FoundLibName);
                    Report.Add('   Fixed Source Lib : ' + FoundLibName);
                end
                else
                    Report.Add(' Component Source Lib NOT Found ! ');
            end; // is Sch Sheet

            ImplIterator := Component.SchIterator_Create;
            ImplIterator.AddFilter_ObjectSet(MkSet(eImplementation));

            Try
                SchImpl := ImplIterator.FirstSchObject;
                While SchImpl <> Nil Do
                Begin
                    Report.Add(' Implementation Model details:');
                    Report.Add('   Name : ' + SchImpl.ModelName + '   Type : ' + SchImpl.ModelType +
                                   '   Description : ' + SchImpl.Description);
                    Report.Add('   Map :  ' + SchImpl.MapAsString);

                    If SchImpl.ModelType = cModelType_PCB Then
                    begin
                        If (SchLibDoc.ObjectID = eSheet) and SchImpl.IsCurrent Then
                            Report.Add(' Is Current (default) FootPrint Model:');

                        If SchImpl.DatafileLinkCount = 0 then // missing FP PcbLib link
                        begin
                            SchImpl.AddDataFileLink(SchImpl.ModelName, '', cModelType_PCB);
                        end;

                        SchImpl.DatalinksLocked := False;
                        ModelDataFile := SchImpl.DatafileLink(0);
                        FoundLibName := '*';
                        If Assigned(ModelDataFile) Then
                        begin
                            FoundLibName := ModelDataFile.Location;
                            Report.Add(' Implementation Data File Link :');
                            Report.Add('   File Location: ' + FoundLibName);
                            //            + ', Entity Name: '    + ModelDataFile.EntityName
                            //            + ', FileKind: '       + ModelDataFile.FileKind);
                        end;

                        // unTick the bottom option (IntLib complib) in PCB footprint dialogue
                        SchImpl.UseComponentLibrary := false;

                        // Look for a footprint models in .PCBLIB    ModelType      := 'PCBLIB';
                        // Want SchDoc to link to source Libs.
                        Found := FindProjectSourceLib(Prj, cDocKind_PcbLib, SchImpl.ModelName, TopLevelLoc);

                        FoundLibName := ExtractFilename(TopLevelLoc);
                        if not Found then Inc(FLinkCount);

                        if Fix and Found then
                        begin
                            ModelDataFile.Location := FoundLibName;
                            Report.Add('   Updated Model Location: ' + FoundLibName);
                            // no point trying update FP description & height in a SchDoc.
                            if SchLibDoc.ObjectID = eSchLib then
                            Begin
                                //FPModel := GetDatafileInLibrary(ModelDataFile.EntityName, eLibSource, InIntLib, FoundLocation);
                                FPModel := PcbServer.LoadCompFromLibrary(SchImpl.ModelName, TopLevelLoc);
                                if FPModel <> NIL then
                                begin
                                    if SchImpl.Description <> FPModel.Description Then
                                       SchImpl.Description := FPModel.Description;
                                    SchImpl.UseComponentLibrary := False;
                                    Report.Add('Updated Component FP Model Desc : '  + SchImpl.Description);
                                    Report.Add('                  FP Height     : '  + CoordUnitToString(FPModel.Height, eMetric));
                                    FPModel := NIL;
                                end;
                            end;
                        end;

                        ModelDFileLoc := ModelDataFile.Location;
                        if trim(ModelDFileLoc) = ''  then ModelDFileLoc := '---->  MISSING <----';
                        Report.Add(' Implementation Data File Link Details : ');
                        Report.Add('   File Location : ' + ModelDFileLoc);
                        Report.Add('');

                    End;
                    SchImpl := ImplIterator.NextSchObject;
                End;

            Finally
                Component.SchIterator_Destroy(ImplIterator);
            End;

            Report.Add('');
            Report.Add('');
            // Send a system notification that component change in the library.
            If Fix Then SchServer.RobotManager.SendMessage(Component.I_ObjectAddress, c_BroadCast, SCHM_EndModify, c_NoEventData);
            Component := Iterator.NextSchObject;
        End;

    Finally
        If Fix Then
            SchLibDoc.GraphicallyInvalidate;
               //CurrentSch.Modified := True;

        If SchLibDoc.ObjectID = eSchLib Then
            // SchDoc.SchLibIterator_Destroy(Iterator)
            SchLibDoc.SchIterator_Destroy(Iterator)
        Else
            SchLibDoc.SchIterator_Destroy(Iterator);
    End;

//    SetDocumentDirty(true);

    GenerateModelsReport(LibDoc, '-CompModels.Txt', SLinkCount, FLinkCount);
    Report.Free;

End;

// direct call
Procedure LinkSchCompsToSourceLibs;
var
    Prj         : IProject;
    Doc         : IDocument;
    SLinkCount  : Integer;            // missing symbol link count
    FLinkCount  : Integer;            // missing footprint model link count
    Fix         : boolean;

begin
    Fix     := true;                  // fix refers to changing lib prefixes

    IntLibMan := IntegratedLibraryManager;
    If IntLibMan = Nil Then Exit;
    WS := GetWorkspace;
    if WS = nil then exit;
    Prj := WS.DM_FocusedProject;
    if Prj = nil then
    begin
        ShowMessage('needs a focused project');
        exit;
    end;
    if Prj.DM_ObjectKindString <> 'PCB Project' then
    begin
        ShowMessage('not a PCB project ');
        exit;
    end;

    if PCBServer = Nil then Client.StartServer('PCB');
    if SchServer = Nil then Client.StartServer('SCH');
    If SchServer = Nil Then Exit;
    If PCBServer = Nil Then Exit;

    Doc := WS.DM_FocusedDocument;

    If Not ((Doc.DM_DocumentKind = cDocKind_SchLib) or (Doc.DM_DocumentKind = cDocKind_Sch)) Then
    Begin
         ShowError('Please focus a Project based SchDoc or SchLib.');
         Exit;
    end;

    SLinkCount := 0;
    FLinkCount := 0;
    LinkSchCompsWrapped(Doc, Fix, SLinkCount, FLinkCount);
end;

// direct call
Procedure LinkPcbFPToSourceLibs;
var
    Prj         : IProject;
    Doc         : IDocument;
    SLinkCount  : Integer;            // missing symbol link count
    FLinkCount  : Integer;            // missing footprint model link count
    Fix         : boolean;

begin
    Fix     := true;                  // fix refers to changing lib prefixes

    IntLibMan := IntegratedLibraryManager;
    If IntLibMan = Nil Then Exit;
    WS := GetWorkspace;
    if WS = nil then exit;
    Prj := WS.DM_FocusedProject;
    if Prj = nil then
    begin
        ShowMessage('needs a focused project');
        exit;
    end;
    if Prj.DM_ObjectKindString <> 'PCB Project' then
    begin
        ShowMessage('not a PCB project ');
        exit;
    end;

    if PCBServer = Nil then Client.StartServer('PCB');
    If PCBServer = Nil Then Exit;

    Doc := WS.DM_FocusedDocument;

    If Not (Doc.DM_DocumentKind = cDocKind_Pcb) Then
    Begin
         ShowError('Please focus a Project based PcbDoc ');
         Exit;
    end;

    SLinkCount := 0;
    FLinkCount := 0;
    LinkFPModelsWrapped (Doc, Fix, SLinkCount, FLinkCount);
end;
{ ..............................................................................
