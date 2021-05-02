{........................................................................................}
{ Summary:  This script can be used to adjust designators on mech layers or              }
{           on silkscreen. The designators are centred, rotated at 0 or 90 deg           }
{           depending on the component orientation and scaled appropriately.             }
{
{   Mechanical Designators are just extra text object(s) that are part of footprint.
    They can be special strings '.Designator' or just text with face value = designator
    The extra designators may be part of the library footprints or added by a
     script CopyDesignatorsToMechLayerPair.pas
}
{ Created by:     Mattias Ericson                                              }
{ Reviewed by:    Petar Perisin                                                }
{ Improvements:   Miroslav Dobrev, Stanislav Popelka                           }
{
 Last Update 30/09/2018 - added stroke font option
 Update 15/03/2016 (Miroslav Dobrev)
  - The script now works with Altium Designer version 14 and greater
  - The script now also works with hidden designator components normally,
    without the need to permanently un-hide the designators first
  - Broken requests to interface elements fixed
  - Other small fixes
 09/04/2021 v2.20 BLM  Support for AD19+ mechlayers, refactored tangled inefficient loops.
 18/04/2021 v2.21 BLM  Minor refactor to CalculateSize() parameters & code formatting.
                       Add constants for stroke text width ratios on mech & overlay layers
                       Fix the Layer selection for Mech. Desg. & adjust width
                       Separate all setup of Mech. Desg. from Comp Designator
 20/04/2021 v2.22 BLM  Allow for Mech Desig. to use MultiLine
 23/04/2021 v2.23 BLM  Get TTF to scale same as stroke. Uses Bounding Rect for Mech Desg. text.
 01/05/2021 v2.24 BLM  Tweak text fn order to fix text selection post adjustment.
 02/05/2021 v2.30 BLM  Comp.Name is not reliable in AD20+, use text box size methods. 

Warning:
  Scripting API can NOT be used (easily) to determine the Top & Bottom side mech layer pairs.

 Multi-Line Text:
 Almost eliminates the small offsets & has near perfect centering.
 Closing & reopening PcbDoc causes Multiline bounding rect to be resized & if text is special string then this
 rectangle box is larger & has an offset.
 Can NOT use IPCB_Text.MultilineTextAutoPosition := eAutoPos_CenterCenter; but use eAutoPos_CenterLeft or other.
 To minimise the offset use UPPERCASE special string & CenterLeft alignment. NO perfect combo found yet!!!
 Designators are typically uppercase can so use '.DESIGNATOR' to avoid the descender of 'g' resizing & offsetting..
 For FP with multi-Layer it seems to make grab rectangle larger.

..........................................................................................}

const
    AD19VersionMajor  = 19;
    AD17MaxMechLayers = 32;
    AD19MaxMechLayers = 1024;

    cMinSilkTextWidth   = 1;
    cSilkTextWidthRatio = 5;      // ratio of text (height / width) for Overlay/silk layers
    cTextWidthRatio     = 10;     // ratio for non-Overlay layer text
//    cUseMultiLineText   = true;   // minimises the tiny offset errors from normal text bounding rect.
    cCloseAfterRun      = false;
    cTextBoxReduction   = 0.5;    // text size/height reduction factor
    cOVLTextReduction   = 0.7;    // Overlay text size/height reduction factor
    cTTFScaleFactor     = 1.75;   // equivalent height TTF to stroke, only used for limits testing.

var
    VerMajor        : WideString;
    LegacyMLS       : boolean;
    Board           : IPCB_Board;
    LayerStack      : IPCB_LayerStack_V7;
    LayerObj        : IPCB_LayerObject_V7;
    MechLayer1      : IPCB_MechanicalLayer;
    MechLayer2      : IPCB_MechanicalLayer;
    MechLayerPair   : TMechanicalLayerPair;
    MechLayerPairs  : IPCB_MechanicalLayerPairs;
    MaxMechLayers   : integer;
    ML1, ML2        : integer;
    slMechPairs     : TStringList;
    slMechSingles   : TStringList;
    slMechPairSides : TStringList;

function Version(const dummy : boolean) : TStringList;         forward;
function IsStringANum(Tekst : String) : Boolean;               forward;
function BoundingRectForObjects(Comp : IPCB_Component, ObjSet : TObjectSet, Layers : IPCB_LayerSet,
                                var Count : integer) : TCoordRect;                                  forward;
function InCompLayerPair(Layer : TLayer) : integer;                                                 forward;
function CalculatePosition(CBR : TCoordRect, MechDes : IPCB_Text, BoardSide : integer) : TLocation; forward;
function CalcBRScale(CBR, TBR : TCoordRect, const ReduceFactor : float) : float;                    forward;
function CalcTextBR(Text : IPCB_Text) : TCoordRect;                                                 forward;
function ClipTextSize(Size : TCoord, MinHeight, MaxHeight : TCoord, TTFont : boolean) : TCoord;     forward;
procedure ProcessFPDesignators(const dummy : integer);                                              forward;
function GetDesignators(PComp : IPCB_Component) : TObjectList;                                      forward;

procedure TFormAdjustDesignators.ButtonCancelClick(Sender: TObject);
begin
    slMechPairs.Clear;
    slMechSingles.Clear;
//    slMechPairSides.Clear;
   Close;
end;

procedure TFormAdjustDesignators.FormAdjustDesignatorsShow(Sender: TObject);
var
    i, j            : Integer;

begin
    ComboBoxLayers.Clear;
    ComboBoxDesignators.Clear;

    LayerStack := Board.LayerStack_V7;

// are any layer pairs defined ?..
    if MechLayerPairs.Count = 0 then
    begin
        RadioButtonSingle.Checked := true;   // does not use Delphi VCL cbChecked
        RadioButtonPair.Enabled := False;
//        ComboBoxLayers.Text := 'Choose a Mech Layer:';
        RadioButtonLayerSingle.Checked := True;
        RadioButtonLayerPair.Enabled := False;
    end else
    begin
// nice clean simple loop of the defined pairs.. err no.
        MechLayerPair := TMechanicalLayerPair;
        MechLayerPair := MechLayerPairs.LayerPair(0);
//       MechLayerPair.Layer1;   // bork
    end;

    for i := 1 to MaxMechLayers do
    begin
        ML1 := LayerUtils.MechanicalLayer(i);
        MechLayer1 := LayerStack.LayerObject_V7(ML1);

        if MechLayer1.MechanicalLayerEnabled then
        begin
            slMechSingles.Add(Board.LayerName(ML1));

            if (RadioButtonPair.Checked) then
            begin
                for j := (i + 1) to MaxMechLayers do
                begin
                    ML2 := LayerUtils.MechanicalLayer(j);
                    MechLayer2 := LayerStack.LayerObject_V7(ML2);

                    if MechLayer2.MechanicalLayerEnabled then
                    if MechLayerPairs.PairDefined(ML1, ML2) then
                    begin
                        slMechPairs.Add(Board.LayerName(ML1) + '=' + Board.LayerName(ML2));
                        ComboBoxLayers.Items.Add(Board.LayerName(ML1) + ' <----> ' + Board.LayerName(ML2));
                        if ComboBoxLayers.Items.Count = 1 then
                            ComboBoxLayers.SetItemIndex(0);

                        ComboBoxDesignators.Items.Add(Board.LayerName(ML1) + ' <----> ' + Board.LayerName(ML2));
                        if ComboBoxDesignators.Items.Count = 1 then
                            ComboBoxDesignators.SetItemIndex(0);

//                        slMechPairSides.Add(IntToStr(ML1) + '=' + IntToStr(eTopSide));
//                        slMechPairSides.Add(IntToStr(ML2) + '=' + IntToStr(eBottomSide));
                    end;
                end;  // j
            end else
            begin
                ComboBoxLayers.Items.Add(Board.LayerName(ML1));
                if ComboBoxLayers.Items.Count = 1 then
                    ComboBoxLayers.SetItemIndex(0);

                ComboBoxDesignators.Items.Add(Board.LayerName(ML1));
                if ComboBoxDesignators.Items.Count = 1 then
                    ComboBoxDesignators.SetItemIndex(0);
            end;
        end;
    end;
end;

procedure TFormAdjustDesignators.RadioButtonSingleClick(Sender: TObject);
var
    i : Integer;
begin

    ComboBoxDesignators.Clear;

    for i := 0 to (slMechSingles.Count - 1) do
    begin
        ComboBoxDesignators.Items.Add(slMechSingles[i]);
    end;
    if slMechSingles.Count > 0 then
        ComboBoxDesignators.SetItemIndex(0);

end;

procedure TFormAdjustDesignators.RadioButtonPairClick(Sender: TObject);
var
    i : integer;
begin

    ComboBoxDesignators.Clear;

    for i := 0 to (slMechPairs.Count - 1) do
    begin
        ComboBoxDesignators.Items.Add( slMechPairs.Names(i) + ' <----> ' + slMechPairs.ValueFromIndex(i) );
    end;
    if slMechPairs.Count > 0 then
        ComboBoxDesignators.SetItemIndex(0);
end;

procedure TFormAdjustDesignators.RadioButtonLayerPairClick(Sender: TObject);
var
    i : integer;
begin

    ComboBoxLayers.Clear;

    for i := 0 to (slMechPairs.Count - 1) do
    begin
        ComboBoxLayers.Items.Add( slMechPairs.Names(i) + ' <----> ' + slMechPairs.ValueFromIndex(i) );
    end;
    if slMechPairs.Count > 0 then
        ComboBoxLayers.SetItemIndex(0);
end;

procedure TFormAdjustDesignators.RadioButtonLayerSingleClick(Sender: TObject);
var
    i : Integer;
begin

    ComboBoxLayers.Clear;

    for i := 0 to (slMechSingles.Count - 1) do
    begin
        ComboBoxLayers.Items.Add(slMechSingles[i]);
    end;
    if slMechSingles.Count > 0 then
        ComboBoxLayers.SetItemIndex(0);
end;

procedure TFormAdjustDesignators.ButtonOKClick(Sender: TObject);
begin
    if (CheckBoxOverlay.Checked) or (CheckBoxMech.Checked) then
        ProcessFPDesignators(0);

    if cCloseAfterRun then
        TFormAdjustDesignators.ButtonCancelClick(Sender)
end;

procedure ProcessFPDesignators(const dummy : integer);
Var
    Track                   : IPCB_Primitive;
    GroupIterator           : IPCB_GroupIterator;
    Component               : IPCB_Component;
    ComponentIterator       : IPCB_BoardIterator;
    ASetOfLayers            : IPCB_LayerSet;
    S                       : TPCBString;
    TrackCount              : Integer;
    dX, dY                  : Integer;
    X, Y                    : TCoord;
    MDLocation              : TLocation;
    Size, Width             : Integer;
    TextWidthRatio          : double;
    Designator              : IPCB_Text;
    MechDesignator          : IPCB_Text;

    PCBSystemOptions        : IPCB_SystemOptions;
    DRCSetting              : boolean;

    CBR, TBR                : TCoordRect;
    TScale                  : float;
    TTFFactor               : float;
    i                       : integer;
    MaximumHeight           : TCoord;   // TCoord from mils in UI
    MinimumHeight           : TCoord;   //
    UnHideDesignators       : Boolean;  // Unhides all designators
    LockStrings             : Boolean;  // Lock all strings
    BoundingLayers          : Boolean;  // Look for bounding rectangle in selected layers
    ShowOnce                : Boolean;
    MoveOverlayText         : boolean;
    UseMultilineText        : boolean;

    Layer1                  : TLayer;
    Layer2                  : TLayer;    // Change this to the layer/layers that best represent the component
    Layer3                  : Integer;   // In many cases eTopOverlay OR eBottomOverLay will be used
    Layer4                  : Integer;   
    MDLayer3                : integer;   // mech designator layers
    MDLayer4                : Integer;
    BoardSide               : integer;

begin
    // Disables Online DRC during designator movement to improve speed
    PCBSystemOptions := PCBServer.SystemOptions;
    If PCBSystemOptions <> Nil Then
    begin
        DRCSetting := PCBSystemOptions.DoOnlineDRC;
        PCBSystemOptions.DoOnlineDRC := false;
    end;

    LayerStack := Board.LayerStack_V7;

    // load various settings from form/dialog
    // User defined Minimum Stroke Font Height in Mils
    if (RadioButtonMM.Checked) then
    begin
        MaximumHeight := MMsToCoord(StrToFloat(EditMaxHeight.Text));
        MinimumHeight := MMsToCoord(StrToFloat(EditMinHeight.Text));
    end else
    begin
        MaximumHeight := MilsToCoord(StrToFloat(EditMaxHeight.Text));
        MinimumHeight := MilsToCoord(StrToFloat(EditMinHeight.Text));
    end;

    if (CheckBoxUnhide.Checked) then UnHideDesignators := True
    else                             UnHideDesignators := False;

    if (CheckBoxLock.Checked) then LockStrings := True
    else                           LockStrings := False;

    if (CheckBoxOverlayPrimitives.Checked) or (CheckBoxMechPrimitives.Checked) then
        BoundingLayers := True
    else BoundingLayers := False;

    if (CheckBoxOverlayPrimitives.Checked) then
    begin
        Layer1 := eTopOverlay;
        Layer2 := eBottomOverlay;
    end else
    begin
        Layer1 := false;
        Layer2 := false;
    end;

    if (cbxUseMultiline.Checked) then UseMultilineText := true
    else                            UseMultilineText := false;

    Layer3   := 0; Layer4   := 0;
    MDLayer3 := 0; MDLayer4 := 0;

    for i := 1 to MaxMechLayers do
    begin
        ML1 := LayerUtils.MechanicalLayer(i);
        MechLayer1 := LayerStack.LayerObject_V7[ML1];

        if (CheckBoxMechPrimitives.Checked) then
        begin
            if (RadioButtonLayerPair.Checked) then
            begin
                if slMechPairs.Names(ComboBoxLayers.GetItemIndex)          = MechLayer1.Name then
                    Layer3 := ML1;
                if slMechPairs.ValueFromIndex(ComboBoxLayers.GetItemIndex) = MechLayer1.Name then
                    Layer4 := ML1;
            end else
            begin
                if ComboBoxLayers.Text := MechLayer1.Name then
                begin
                    Layer3 := ML1;
                    Layer4 := ML1;
                end;
            end;
        end;

        if (CheckBoxMech.Checked) then
        begin
            if (RadioButtonPair.Checked) then
            begin
                if slMechPairs.Names(ComboBoxDesignators.GetItemIndex)          = MechLayer1.Name then
                    MDLayer3 := ML1;
                if slMechPairs.ValueFromIndex(ComboBoxDesignators.GetItemIndex) = MechLayer1.Name then
                    MDLayer4 := ML1;
            end else
            begin
                if ComboBoxDesignators.Text = MechLayer1.Name then   // slMechSingles(ComboBoxDesignators.GetItemIndex)
                begin
                    MDLayer3 := ML1;
                    MDLayer4 := ML1;
                end;
           end;
        end;
    end;  // for

    PCBServer.PreProcess;

    ASetOfLayers := LayerSetUtils.SignalLayers;
    ComponentIterator := Board.BoardIterator_Create;
    ComponentIterator.AddFilter_ObjectSet(MkSet(eComponentObject));
    ComponentIterator.AddFilter_IPCB_LayerSet(ASetOfLayers);
    ComponentIterator.AddFilter_Method(eProcessAll);
    Component := ComponentIterator.FirstPCBObject;

    while (Component <> Nil) Do
    begin
        Component.BeginModify;

     // Unhide designator visibility
        if UnHideDesignators then
            Component.NameOn := true;
        // Lock all strings?
        if LockStrings = true then
            Component.LockStrings := true;
        
        ASetOfLayers := LayerSetUtils.EmptySet;
        if Layer1 <> 0 then ASetOfLayers.Include(Layer1);
        if Layer2 <> 0 then ASetOfLayers.Include(Layer2);
        if Layer3 <> 0 then ASetOfLayers.Include(Layer3);
        if Layer4 <> 0 then ASetOfLayers.Include(Layer4);

        TrackCount := 0;
//   Look for component's tracks on the layers chosen under settings only when BoundingLayers is true
        if (BoundingLayers) Then
            CBR := BoundingRectForObjects(Component, MkSet(eTrackObject, eArcObject), ASetOfLayers, TrackCount);

//   Calculate the width and height of the bounding rectangle
        if TrackCount < 1 then
        begin
//   Component.BoundingRectangleNoNameComment includes eTextObject which is bad bad bad..
            ASetOfLayers.IncludeSignalLayers;                    // top FP may only have bottom side pads.
            ASetOfLayers.Include(eMultiLayer);                   // TH pad & via?
            CBR := BoundingRectForObjects(Component, MkSet(ePadObject, eTrackObject, eArcObject, eRegionObject), ASetOfLayers, TrackCount);
        end;

        dY := RectHeight(CBR);
        dX := RectWidth(CBR);
//   test if dX or dY too small !

        Designator        := GetDesignators(Component).Items(0);

//   Size limits depend on rotation & component primitives bounding rectangle
        if ((Length(Designator.GetDesignatorDisplayString) > 7) and (ShowOnce = False)) then
        begin
            ShowMessage('Designator too long in one or more components such as (' + Designator.Text + ').' + #13 + 'More than 7 characters are not supported, these components will be skipped.');
            ShowOnce := True;
        end;


        if (CheckBoxOverlay.Checked) then
        begin
//            Component.Comment.BeginModify;
            Component.Name.BeginModify;

            // Setup the text properties
            Width                 := Designator.Width;
            Designator.UseTTFonts := True;
            Designator.Italic     := False;
            Designator.Bold       := True;
            Designator.Inverted   := False;
            Designator.FontName   := 'Microsoft Sans Serif';

            // Thicker strokes for Overlay text
            TextWidthRatio := cTextWidthRatio;
            MoveOverlayText := true;
            if (Designator.Layer = eTopOverlay) or (Designator.Layer = eBottomOverlay) then
            begin
                MoveOverlayText := false;
                if (cbxMoveOverlayText.Checked) then MoveOverlayText := true;
                TextWidthRatio := cSilkTextWidthRatio;
            end;

            If (cbxUseStrokeFonts.Checked) then
                Designator.UseTTFonts := False;

//     Rotate the designator to increase the readability
            BoardSide := InCompLayerPair(Component.Layer);  // Designator.Layer);
            if MoveOverlayText then
            begin
                if dY > dX then
                begin
                    if BoardSide = eTopSide then
                        Designator.Rotation := 90
                    else
                        Designator.Rotation := 270;
                end
                else
                    Designator.Rotation := 0;
            end;

//     Set the size based on the component primitives bounding rectangle
            Designator.SetState_XSizeYSize;
            TBR    := CalcTextBR(Designator);
            TScale := CalcBRScale(CBR, TBR, cOVLTextReduction);
            Size   := Designator.Size * TScale;

//     Trim down designator if its size is bigger or maller than M...mumHeight consts
            Size := ClipTextSize(Size, MinimumHeight, MaximumHeight, Designator.UseTTFonts);

            Width := Size / TextWidthRatio;
            if (Designator.Layer = eTopOverlay) or (Designator.Layer = eBottomOverlay) then
                if Width < cMinSilkTextWidth then Width := cMinSilkTextWidth;

            Designator.Size  := Size;
            Designator.Width := Width;
            Component.Name.EndModify;

            if MoveOverlayText then
            begin
                MDLocation := CalculatePosition(CBR, Designator, BoardSide);
                Designator.MoveToXY(MDLocation.X, MDLocation.Y);
             end;
//            Component.Comment.EndModify;
        end;

        if (CheckBoxMech.Checked) then
        begin
            ASetOfLayers := LayerSetUtils.EmptySet;
            if MDLayer3 <> 0 then ASetOfLayers.Include(MDLayer3);
            if MDLayer4 <> 0 then ASetOfLayers.Include(MDLayer4);
            GroupIterator := Component.GroupIterator_Create;
            GroupIterator.AddFilter_ObjectSet(MkSet(eTextObject));
            GroupIterator.AddFilter_IPCB_LayerSet(ASetOfLayers);

            MechDesignator := GroupIterator.FirstPCBObject;
            while (MechDesignator <> Nil) Do
            begin
                if not MechDesignator.IsDesignator then
                if ASetOfLayers.Contains(MechDesignator.Layer) then
                if ( (LowerCase(MechDesignator.GetState_UnderlyingString) = '.designator') or (MechDesignator.GetState_ConvertedString = Designator.GetState_ConvertedString) ) then
                begin
                    // Thicker strokes for Overlay text
                    TextWidthRatio := cTextWidthRatio;
                    MoveOverlayText := true;
                    if (MechDesignator.Layer = eTopOverlay) or (MechDesignator.Layer = eBottomOverlay) then
                    begin
                        MoveOverlayText := false;
                        if (cbxMoveOverlayText.Checked) then MoveOverlayText := true;
                        TextWidthRatio := cSilkTextWidthRatio;
                    end;

//         Can not determine the "side" of the comp mech layer pairs so use Component Layer.
                    BoardSide := InCompLayerPair(Component.Layer);

//         Rotate the mech designator to increase the readability
                    if MoveOverlayText then
                    begin
                        if dY > dX then
                        begin
                            if BoardSide = eTopSide then
                                MechDesignator.Rotation := 90
                            else
                                MechDesignator.Rotation := 270;
                        end
                        else
                            MechDesignator.Rotation := 0;
                    end;

                    If (cbxUseStrokeFonts.Checked) then
                        MechDesignator.UseTTFonts := False
                    else
                        MechDesignator.UseTTFonts := True;

                    if (UseMultiLineText) then
                    begin
                        MechDesignator.SetState_Multiline(true);
                        MechDesignator.MultilineTextAutoPosition :=  eAutoPos_CenterLeft;
//         trick to get multiline box to resize.
                        MechDesignator.SetState_MultilineTextHeight(0);
                        MechDesignator.SetState_MultilineTextWidth(0);
                    end
                        else MechDesignator.SetState_Multiline(false);

//         Set the size based on the component bounding rectangle H & W
                    MechDesignator.SetState_XSizeYSize;
                    TBR    := CalcTextBR(MechDesignator);
                    TScale := CalcBRScale(CBR, TBR, cTextBoxReduction);
                    Size   := MechDesignator.Size * TScale;

//         Trim down designator if its size is bigger or smaller than the M..mumHeight consts
                    Size := ClipTextSize(Size, MinimumHeight, MaximumHeight, Designator.UseTTFonts);

                    Width := Size / TextWidthRatio;
                    if (MechDesignator.Layer = eTopOverlay) or (MechDesignator.Layer = eBottomOverlay) then
                        if Width < cMinSilkTextWidth then Width := cMinSilkTextWidth;

                    MechDesignator.Size  := Size;
                    MechDesignator.Width := Width;

//         force refresh of bonding rect (still wrong after close & reopen of PcbDoc)
                    if (UseMultiLineText) then
                    begin
                        MechDesignator.SetState_MultilineTextHeight(0);
                        MechDesignator.SetState_MultilineTextWidth(0);
                    end;

                    if MoveOverlayText then
                    begin
                        MDLocation := CalculatePosition(CBR, MechDesignator, BoardSide);
                        MechDesignator.MoveToXY(MDLocation.X, MDLocation.Y);
                    end;
                    MechDesignator.SetState_XSizeYSize;
                    MechDesignator.GraphicallyInvalidate;
                end;

                MechDesignator := GroupIterator.NextPCBObject;
            end;
            // Destroy mech text interator
            Component.GroupIterator_Destroy(GroupIterator);
        end;

        Component.EndModify;
        Component.SetState_XSizeYSize;
        Component.GraphicallyInvalidate;

        Component := ComponentIterator.NextPCBObject;
    end;
    // Destroy the component iterator
    Board.BoardIterator_Destroy(ComponentIterator);

    // Notify the pcbserver that all changes have been made
    PCBServer.PostProcess;
    //Refresh the screen
    Client.SendMessage('PCB:Zoom', 'Action=Redraw' , 255, Client.CurrentView);

    // Restore DRC setting
    If PCBSystemOptions <> Nil Then
        PCBSystemOptions.DoOnlineDRC := DRCSetting;

end;

procedure TFormAdjustDesignators.CheckBoxMechClick(Sender: TObject);
begin
   If (CheckBoxMech.Checked) then
   begin
      if MechLayerPairs.Count <> 0 then
         RadioButtonPair.Enabled := True;
      RadioButtonSingle.Enabled   := True;
      ComboBoxDesignators.Enabled := True;
   end
   else
   begin
      RadioButtonPair.Enabled     := False;
      RadioButtonSingle.Enabled   := False;
      ComboBoxDesignators.Enabled := False;
   end;
end;

procedure TFormAdjustDesignators.CheckBoxMechPrimitivesClick(Sender: TObject);
begin
   If (CheckBoxMechPrimitives.Checked) then
   begin
      if MechLayerPairs.Count <> 0 then
         RadioButtonLayerPair.Enabled := True;
      RadioButtonLayerSingle.Enabled := True;
      ComboBoxLayers.Enabled         := True;
   end
   else
   begin
      RadioButtonLayerPair.Enabled   := False;
      RadioButtonLayerSingle.Enabled := False;
      ComboBoxLayers.Enabled         := False;
   end;
end;

procedure TFormAdjustDesignators.EditMinHeightChange(Sender: TObject);
begin
   if not IsStringANum(EditMinHeight.Text) then
   begin
      ButtonOK.Enabled := False;
      EditMinHeight.Font.Color := clRed;
   end
   else
   begin
      EditMinHeight.Font.Color := clWindowText;
      if IsStringANum(EditMaxHeight.Text) then
         ButtonOK.Enabled := True;
   end;
end;

procedure TFormAdjustDesignators.EditMaxHeightChange(Sender: TObject);
begin
   if not IsStringANum(EditMaxHeight.Text) then
   begin
      ButtonOK.Enabled := False;
      EditMaxHeight.Font.Color := clRed;
   end
   else
   begin
      EditMaxHeight.Font.Color := clWindowText;
      if IsStringANum(EditMinHeight.Text) then
         ButtonOK.Enabled := True;
   end;
end;

Procedure Start;
begin
    Board := PCBServer.GetCurrentPCBBoard;
    if Board = nil then
    begin
        ShowMessage('Focused Doc Not a .PcbDoc ');
        exit;
    end;

//  Check AD version for layer stack version
    VerMajor := Version(true).Strings(0);
    MaxMechLayers := AD17MaxMechLayers;
    LegacyMLS     := true;
    if (StrToInt(VerMajor) >= AD19VersionMajor) then
    begin
        LegacyMLS     := false;
        MaxMechLayers := AD19MaxMechLayers;
    end;

    slMechPairs     := TStringList.Create;
    slMechPairs.StrictDelimiter := true;
    slMechPairs.NameValueSeparator := '=';

    slMechSingles   := TStringList.Create;
//    slMechPairSides := TStringList.Create;
//    slMechPairSides.Delimiter := '|';
//    slMechPairSides.StrictDelimiter := true;
//    slMechPairSides.NameValueSeparator := '=';
//    slMechPairSides.Duplicates := dupIgnore;

    MechLayerPairs  := Board.MechanicalPairs;

    FormAdjustDesignators.Show;   //Modal;
end;

{.......................................................................................}
function GetDesignators(PComp : IPCB_Component) : TObjectList;
//Comp.Name is not reliable in AD20+ ?? Is there now more than ONE?
var
    I     : integer;
    PText : IPCB_Text;
begin
    Result := TObjectList.Create;
    for I := 1 to PComp.GetPrimitiveCount(MkSet(eTextObject)) do
    begin
        PText := PComp.GetPrimitiveAt(I, eTextObject);
        if PText.IsDesignator then
            Result.Add(PText);        
    end;
end;

function ClipTextSize(Size : TCoord, MinHeight, MaxHeight : TCoord, TTFont : boolean) : TCoord;
var
    Min, Max : TCoord;
begin
    Result := Size; 
    Min := MinHeight;
    Max := MaxHeight;
    if TTFont then
    begin
        Min := MinHeight * cTTFScaleFactor;;
        Max := MaxHeight * cTTFScaleFactor;;
    end;

    if Result  > Max then
        Result  := Max;
    if Result  <  Min then
        Result  := Min;
end;

function CalcBRScale(CBR, TBR : TCoordRect, const ReduceFactor : float) : float;
var
   SX, SY : double;
begin
    SX := RectWidth(CBR) * ReduceFactor / RectWidth(TBR);
    SY := RectHeight(CBR) * ReduceFactor / RectHeight(TBR);
    Result := SX;
    if SY < SX then Result := SY;
end;

function CalcTextBR(Text : IPCB_Text) : TCoordRect;
var
    GMPC1          : IPCB_GeometricPolygon;
    VL             : Pgpc_vertex_list;
    X1, X2, Y1, Y2 : TCoord;
    I, J           : integer;

begin
    X1 := kMaxCoord; X2 := kMinCoord;
    Y1 := kMaxCoord; Y2 := kMinCoord;

    if Text.TextKind = eText_TrueTypeFont then
    begin
        GMPC1 := Text.TTTextOutlineGeometricPolygon;
        for I := 0 to (GMPC1.Count - 1) do
        begin
             VL := GMPC1.Contour(I);
             for J := 0 to (VL.Count - 1) do
             begin
                 X1 := Min(X1, VL.x(J));
                 X2 := Max(X2, VL.x(J));
                 Y1 := Min(Y1, VL.y(J));
                 Y2 := Max(Y2, VL.y(J));
            end;
        end;
        Result := RectToCoordRect( Rect(X1, Y2, X2, Y1) );
    end
    else
       Result := Text.BoundingRectangleForSelection;
end;

function CalculatePosition(CBR : TCoordRect, MechDes : IPCB_Text, BoardSide : integer) : TLocation;
var
    X, Y : TCoord;
    TBR  : TCoordRect;
begin
    Result := TLocation;
    MechDes.SetState_XSizeYSize;
    TBR := MechDes.BoundingRectangleForSelection;

    X := (CBR.Left + CBR.Right ) / 2;
    Y := (CBR.Top  + CBR.Bottom) / 2;

    if BoardSide = eTopSide then
    begin
        case MechDes.Rotation of
          360, 0 :
            begin
                X := X - RectWidth(TBR) / 2;
                Y := Y - RectHeight(TBR) / 2;
            end;
          90 :
            begin
                X := X + RectWidth(TBR) / 2;
                Y := Y - RectHeight(TBR) / 2;
            end;
          180 :
            begin
                X := X + RectWidth(TBR) / 2;
                Y := Y + RectHeight(TBR) / 2;
            end;
          270 :
            begin
                X := X - RectWidth(TBR) / 2;
                Y := Y + RectHeight(TBR) / 2;
            end;
        end;
    end;
    if BoardSide = eBottomSide then
    begin
        case MechDes.Rotation of
          360, 0 :
            begin
                X := X + RectWidth(TBR) / 2;
                Y := Y - RectHeight(TBR) / 2;
            end;
          90 :
            begin
                X := X + RectWidth(TBR) / 2;
                Y := Y + RectHeight(TBR) / 2;
            end;
          180 :
            begin
                X := X - RectWidth(TBR) / 2;
                Y := Y + RectHeight(TBR) / 2;
            end;
          270 :
            begin
                X := X - RectWidth(TBR) / 2;
                Y := Y - RectHeight(TBR) / 2;
            end;
        end;
    end;
    Result := Point(X, Y);
end;

function BoundingRectForObjects(Comp : IPCB_Component, ObjSet : TObjectSet, Layers : IPCB_LayerSet, var Count : integer) : TCoordRect;
var
    Prim         : IPCB_Primitive;
    GIterator    : IPCB_GroupIterator;
    PBR          : TRect;
    X1,X2,Y1,Y2  : TCoord;

begin
    X1 := kMaxCoord; X2 := kMinCoord;
    Y1 := kMaxCoord; Y2 := kMinCoord;
    Count := 0;

    GIterator := Comp.GroupIterator_Create;
    GIterator.AddFilter_ObjectSet(ObjSet);
    GIterator.AddFilter_IPCB_LayerSet(Layers);     // dnw ?

    Prim := GIterator.FirstPCBObject;
    while Prim <> Nil Do
    begin
        if Layers.Contains(Prim.Layer) then
        begin
            inc(Count);
            PBR := CoordRectToRect(Prim.BoundingRectangle);

            X1 := Min(X1, PBR.Left);
            X2 := Max(X2, PBR.Right);
            Y1 := Min(Y1, PBR.Bottom);
            Y2 := Max(Y2, PBR.Top);
        end;
        Prim := GIterator.NextPCBObject;
    end;
    Comp.GroupIterator_Destroy(GIterator);
                                  // l,  t,  r, b
    Result := RectToCoordRect( Rect(X1, Y2, X2, Y1) );
    if (Result.Left   = kMaxCoord) then Result.Left   := Comp.X;
    if (Result.Bottom = kMaxCoord) then Result.Bottom := Comp.Y;
    if (Result.Top    = kMinCoord) then Result.Top    := Comp.Y;
    if (Result.Right  = kMinCoord) then Result.Right  := Comp.X;
end;

// Function that checks is string a float number or not
function IsStringANum(Tekst : String) : Boolean;
var
    i        : Integer;
    dotCount : Integer;
    ChSet    : TSet;
begin
    Result := True;
    // Test for number, dot or comma
    ChSet := SetUnion(MkSet(Ord('.'),Ord(',')), MkSetRange(Ord('0'), Ord('9')) );
    for i := 1 to Length(Tekst) do
       if not InSet(Ord(Tekst[i]), ChSet) then Result := false;

    // Test if we have more than one dot or comma
    dotCount := 0;
    ChSet := MkSet(Ord('.'),Ord(','));
    for i := 1 to Length(Tekst) do
       if InSet(Ord(Tekst[i]), ChSet) then
          Inc(dotCount);

    if dotCount > 1 then Result := False;
end;

function InCompLayerPair(Layer : TLayer) : integer;
//  returns: 0= no side, eTopSide, eBottomSide
var
    index : integer;
begin
    Result := 0;
    case Layer of
      eTopLayer,    eTopSolder,     eTopOverlay,    eTopPaste    : Result := eTopSide;
      eBottomLayer, eBottomSolder , eBottomOverlay, eBottomPaste : Result := eBottomSide;
// invalid to assume mech layer pair order is top-bottom; top-bottom etc..
// NO solution..
{      else
        begin
            index := slMechPairSides.IndexOfName(IntToStr(Layer));
            if index > 0 then
                Result := slMechPairSides.ValueFromIndex(index);
        end;
}
    end;
end;

function Version(const dummy : boolean) : TStringList;
begin
    Result               := TStringList.Create;
    Result.Delimiter     := '.';
    Result.Duplicates    := dupAccept;
    Result.DelimitedText := Client.GetProductVersion;
end;
