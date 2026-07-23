function dpcQPIApp()
%DPCQPIAPP  Four-direction DPC-QPI processing GUI for mouse kidney tissue.
%
% VERSION 1 (this file): loading, registration, normalization, DPC-TB/LR,
% phase reconstruction (calibrated Mode A / qualitative Mode B), phase-map
% display with mouse readout, ROI line/point/rect/polygon profiling, and
% export. Segmentation (glomerulus/tubule/lumen) is VERSION 2 - the
% "Segment" button and the measurement panel are present as placeholders
% so the overall layout matches the final design, but they do not yet run
% classical segmentation.
%
% ------------------------------------------------------------------
% REQUIRED WORDING / LIMITATIONS (see Section 15 of the spec)
% ------------------------------------------------------------------
% This program performs "QPI-based kidney tissue structural segmentation
% and quantitative morphology analysis" (segmentation lands in Version 2).
% It is NOT a medical diagnostic system and must not be used or presented
% as one. Raw grayscale intensity is never labeled "phase." The Mode B
% gradient-integration result is always labeled "Qualitative phase
% preview" and is never called a calibrated quantitative phase map.
% Physical thickness is only computed when both wavelength and a valid
% refractive-index difference (delta_n) have been entered.
%
% ------------------------------------------------------------------
% REQUIRED MATLAB TOOLBOXES
% ------------------------------------------------------------------
%   - MATLAB (base): uifigure/uigridlayout/uitabgroup/uiaxes/uitable, etc.
%   - Image Processing Toolbox (REQUIRED): imregcorr, imwarp, imtranslate,
%     imref2d, fspecial, imfilter, drawpoint/drawline/drawrectangle/
%     drawpolygon, createMask, unwrap-related (this file uses 2-D phase
%     unwrapping via a simple quality-unaware unwrap - see removePhaseBackground
%     comments), imread for TIFF/PNG/JPG/BMP.
%
% ------------------------------------------------------------------
% HOW TO RUN  (see full instructions in the chat response / comments
% at the end of this file)
% ------------------------------------------------------------------
%   Run:  dpcQPIApp
%   Then: "Load 4 Images" -> browse each of Top/Bottom/Left/Right ->
%         set physical parameters in the Phase Map panel -> "Register" ->
%         "Reconstruct" -> inspect Phase Map / DPC tabs -> draw ROIs ->
%         "Export".

close all force; clc;

% ===================================================================
%                    APPLICATION STATE (shared struct)
% ===================================================================
app = struct();
app.params = defaultParams();
app.disp   = struct('brightness', 0, 'contrast', 1, 'gamma', 1, ...
    'dispMin', 0, 'dispMax', 1);

app.data = struct();
app.data.raw        = emptyDirStruct();
app.data.registered = emptyDirStruct();
app.data.normalized  = emptyDirStruct();
app.data.rawDisplay  = emptyDirStruct();   % original (possibly RGB) images for display only
app.data.shifts      = struct('bottom', [0 0], 'left', [0 0], 'right', [0 0]);
app.data.qc          = struct();
app.data.normFactors = struct();
app.data.dpcTB = []; app.data.dpcLR = [];
app.data.phase = []; app.data.phaseMode = 'B'; app.data.phaseInfo = '';
app.data.opd = []; app.data.thickness = [];
app.data.roiA = []; app.data.roiB = [];
app.data.lastClick = [];

app.ui = struct();

buildUI();
refreshAllDisplays();
updatePhaseDisplay();

% ===================================================================
%                        NESTED UI-BUILDING
% ===================================================================
    function s = emptyDirStruct()
        s = struct('top', [], 'bottom', [], 'left', [], 'right', []);
    end

    function buildUI()
        app.ui.fig = uifigure('Name', 'DPC-QPI Kidney Analysis (Version 1)', ...
            'Position', [40 40 1620 980]);

        mainGrid = uigridlayout(app.ui.fig, [3 1]);
        mainGrid.RowHeight = {56, '1x', 300};
        mainGrid.ColumnWidth = {'1x'};
        app.ui.mainGrid = mainGrid;

        buildToolbar(mainGrid);
        centerGrid = uigridlayout(mainGrid, [2 2]);
        centerGrid.RowHeight = {'1x', '1x'};
        centerGrid.ColumnWidth = {'1x', '1x'};
        centerGrid.Layout.Row = 2; centerGrid.Layout.Column = 1;

        buildDirectionalImagesPanel(centerGrid, 1, 1);
        buildPhasePanel(centerGrid, 1, 2);
        buildDPCPanel(centerGrid, 2, 1);
        buildMeasurementPanel(centerGrid, 2, 2);

        buildBottomTabs(mainGrid);
    end

    function buildToolbar(parentGrid)
        tb = uipanel(parentGrid);
        tb.Layout.Row = 1; tb.Layout.Column = 1;
        g = uigridlayout(tb, [1 8]);
        g.ColumnWidth = {160, 120, 130, 120, '1x', 110, 170, 40};
        g.RowHeight = {'1x'};

        b1 = uibutton(g, 'Text', 'Load 4 Images', 'ButtonPushedFcn', @btnLoad4Images_Callback);
        b1.Layout.Column = 1;
        b2 = uibutton(g, 'Text', 'Register', 'ButtonPushedFcn', @btnRegister_Callback);
        b2.Layout.Column = 2;
        b3 = uibutton(g, 'Text', 'Reconstruct', 'ButtonPushedFcn', @btnReconstruct_Callback);
        b3.Layout.Column = 3;
        b4 = uibutton(g, 'Text', 'Segment', 'ButtonPushedFcn', @btnSegment_Callback);
        b4.Layout.Column = 4;
        b5 = uibutton(g, 'Text', 'Export', 'ButtonPushedFcn', @btnExport_Callback);
        b5.Layout.Column = 6;
        b6 = uibutton(g, 'Text', 'About / Limitations', 'ButtonPushedFcn', @btnAbout_Callback);
        b6.Layout.Column = 7;
    end

    function buildDirectionalImagesPanel(parentGrid, r, c)
        p = uipanel(parentGrid, 'Title', 'Directional Images (2x2: Top/Bottom/Left/Right)');
        p.Layout.Row = r; p.Layout.Column = c;
        g = uigridlayout(p, [2 1]);
        g.RowHeight = {26, '1x'};

        fnRow = uigridlayout(g, [1 4]);
        fnRow.Layout.Row = 1;
        app.ui.lblFileTop    = uilabel(fnRow, 'Text', 'Top: (none)');
        app.ui.lblFileBottom = uilabel(fnRow, 'Text', 'Bottom: (none)');
        app.ui.lblFileLeft   = uilabel(fnRow, 'Text', 'Left: (none)');
        app.ui.lblFileRight  = uilabel(fnRow, 'Text', 'Right: (none)');

        tg = uitabgroup(g);
        tg.Layout.Row = 2;
        app.ui.tgImages = tg;

        tabRaw = uitab(tg, 'Title', 'Raw');
        tabReg = uitab(tg, 'Title', 'Registered');
        tabNorm = uitab(tg, 'Title', 'Normalized');

        [app.ui.axRawTop, app.ui.axRawBottom, app.ui.axRawLeft, app.ui.axRawRight] = ...
            build2x2Axes(tabRaw, {'Top','Bottom','Left','Right'});

        regGrid = uigridlayout(tabReg, [2 1]);
        regGrid.RowHeight = {70, '1x'};
        shiftPanel = buildManualShiftControls(regGrid);
        shiftPanel.Layout.Row = 1;
        regImgHolder = uipanel(regGrid, 'BorderType', 'none');
        regImgHolder.Layout.Row = 2;
        [app.ui.axRegTop, app.ui.axRegBottom, app.ui.axRegLeft, app.ui.axRegRight] = ...
            build2x2Axes(regImgHolder, {'Top (reference)','Bottom','Left','Right'});

        [app.ui.axNormTop, app.ui.axNormBottom, app.ui.axNormLeft, app.ui.axNormRight] = ...
            build2x2Axes(tabNorm, {'Top (normalized)','Bottom (normalized)','Left (normalized)','Right (normalized)'});
    end

    function [axTL, axTR, axBL, axBR] = build2x2Axes(parent, titles)
        g = uigridlayout(parent, [2 2]);
        g.RowHeight = {'1x','1x'}; g.ColumnWidth = {'1x','1x'};
        axTL = uiaxes(g); axTL.Layout.Row = 1; axTL.Layout.Column = 1;
        axTR = uiaxes(g); axTR.Layout.Row = 1; axTR.Layout.Column = 2;
        axBL = uiaxes(g); axBL.Layout.Row = 2; axBL.Layout.Column = 1;
        axBR = uiaxes(g); axBR.Layout.Row = 2; axBR.Layout.Column = 2;
        allAx = [axTL axTR axBL axBR];
        for k = 1:4
            title(allAx(k), titles{k});
            axis(allAx(k), 'image'); axis(allAx(k), 'off');
            colormap(allAx(k), gray);
        end
    end

    function p = buildManualShiftControls(parentGrid)
        p = uipanel(parentGrid, 'Title', 'Manual Shift Override (px, optional)');
        g = uigridlayout(p, [2 8]);
        g.RowHeight = {'1x','1x'};
        lbls = {'Bottom dX','Bottom dY','Left dX','Left dY','Right dX','Right dY'};
        fields = cell(1,6);
        for k = 1:6
            l = uilabel(g, 'Text', lbls{k}); l.Layout.Row = 1; l.Layout.Column = k;
            fields{k} = uieditfield(g, 'numeric', 'Value', 0);
            fields{k}.Layout.Row = 2; fields{k}.Layout.Column = k;
        end
        app.ui.efShiftBottomX = fields{1}; app.ui.efShiftBottomY = fields{2};
        app.ui.efShiftLeftX   = fields{3}; app.ui.efShiftLeftY   = fields{4};
        app.ui.efShiftRightX  = fields{5}; app.ui.efShiftRightY  = fields{6};
        app.ui.cbManualShift = uicheckbox(g, 'Text', 'Use manual shifts above (skip auto-registration)');
        app.ui.cbManualShift.Layout.Row = 1; app.ui.cbManualShift.Layout.Column = [7 8];
    end

    function buildPhasePanel(parentGrid, r, c)
        p = uipanel(parentGrid, 'Title', 'Reconstructed Phase Map');
        p.Layout.Row = r; p.Layout.Column = c;
        g = uigridlayout(p, [3 1]);
        g.RowHeight = {24, '1x', 190};

        topRow = uigridlayout(g, [1 2]);
        topRow.Layout.Row = 1;
        topRow.ColumnWidth = {'1x', '2x'};
        app.ui.lblMode = uilabel(topRow, 'Text', 'Mode: (none)', 'FontWeight', 'bold');
        app.ui.lblReadout = uilabel(topRow, 'Text', 'X: -   Y: -   Phase: -   OPD: -   Thickness: -');

        app.ui.axPhase = uiaxes(g);
        app.ui.axPhase.Layout.Row = 2;
        axis(app.ui.axPhase, 'image');
        app.ui.imgPhaseHandle = imagesc(app.ui.axPhase, zeros(2,2));
        app.ui.imgPhaseHandle.ButtonDownFcn = @onImagePhaseClicked;
        colormap(app.ui.axPhase, parula);
        colorbar(app.ui.axPhase);

        ctrl = uigridlayout(g, [5 8]);
        ctrl.Layout.Row = 3;
        ctrl.RowHeight = {'1x','1x','1x','1x','1x'};

        l = uilabel(ctrl, 'Text', 'Colormap'); l.Layout.Row = 1; l.Layout.Column = 1;
        app.ui.ddColormap = uidropdown(ctrl, 'Items', {'parula','jet','gray','turbo','hot'}, ...
            'ValueChangedFcn', @(~,~) updatePhaseDisplay());
        app.ui.ddColormap.Layout.Row = 1; app.ui.ddColormap.Layout.Column = 2;

        app.ui.efPhaseMin = addParamField(ctrl, 1, 2, 'Phase Min', -pi, @(~,~) updatePhaseDisplay());
        app.ui.efPhaseMax = addParamField(ctrl, 1, 3, 'Phase Max', pi, @(~,~) updatePhaseDisplay());
        app.ui.efRegParam = addParamField(ctrl, 1, 4, 'Reg. Param', app.params.regParam, []);

        app.ui.cbBackgroundSub = uicheckbox(ctrl, 'Text', 'Remove BG');
        app.ui.cbBackgroundSub.Layout.Row = 2; app.ui.cbBackgroundSub.Layout.Column = 1;
        app.ui.ddBackgroundMethod = uidropdown(ctrl, 'Items', {'mean','corners'});
        app.ui.ddBackgroundMethod.Layout.Row = 2; app.ui.ddBackgroundMethod.Layout.Column = 2;
        app.ui.cbUnwrap = uicheckbox(ctrl, 'Text', 'Unwrap phase');
        app.ui.cbUnwrap.Layout.Row = 2; app.ui.cbUnwrap.Layout.Column = 3;
        app.ui.efEpsilon = addParamField(ctrl, 2, 4, 'DPC epsilon', app.params.epsilon, []);

        app.ui.efWavelength = addParamField(ctrl, 3, 1, 'Wavelength (um)', app.params.wavelength_um, []);
        app.ui.efIllumNA    = addParamField(ctrl, 3, 2, 'Illum. NA', app.params.illumNA, []);
        app.ui.efObjNA      = addParamField(ctrl, 3, 3, 'Objective NA', app.params.objNA, []);
        app.ui.efPixelSize  = addParamField(ctrl, 3, 4, 'Pixel size (um)', app.params.pixelSize_um, []);

        app.ui.efDeltaN = addParamField(ctrl, 4, 1, 'Delta n (optional)', NaN, []);
        btnLoadTF = uibutton(ctrl, 'Text', 'Load Transfer Functions...', 'ButtonPushedFcn', @btnLoadTransferFn_Callback);
        btnLoadTF.Layout.Row = 4; btnLoadTF.Layout.Column = [3 4];
        btnRecompute = uibutton(ctrl, 'Text', 'Recompute Phase', 'ButtonPushedFcn', @btnReconstruct_Callback);
        btnRecompute.Layout.Row = 4; btnRecompute.Layout.Column = [5 6];
        note = uilabel(ctrl, 'Text', 'Mode A activates only after valid Hu/Hv transfer functions are loaded.', ...
            'FontAngle','italic', 'FontColor',[0.4 0.4 0.4]);
        note.Layout.Row = 4; note.Layout.Column = [7 8];

        app.ui.lblTransferFnStatus = uilabel(ctrl, 'Text', 'Transfer functions: not loaded (Mode B active)');
        app.ui.lblTransferFnStatus.Layout.Row = 5; app.ui.lblTransferFnStatus.Layout.Column = [1 8];
    end

    function ef = addParamField(grid, row, pairIdx, labelStr, initVal, callback)
        l = uilabel(grid, 'Text', labelStr);
        l.Layout.Row = row; l.Layout.Column = 2*pairIdx-1;
        ef = uieditfield(grid, 'numeric', 'Value', initVal);
        ef.Layout.Row = row; ef.Layout.Column = 2*pairIdx;
        if ~isempty(callback)
            ef.ValueChangedFcn = callback;
        end
    end

    function buildDPCPanel(parentGrid, r, c)
        p = uipanel(parentGrid, 'Title', 'DPC-TB / DPC-LR & Display-Only Controls');
        p.Layout.Row = r; p.Layout.Column = c;
        g = uigridlayout(p, [2 1]);
        g.RowHeight = {'1x', 150};

        imgRow = uigridlayout(g, [1 2]);
        imgRow.Layout.Row = 1;
        app.ui.axDPC_TB = uiaxes(imgRow); app.ui.axDPC_TB.Layout.Column = 1;
        app.ui.axDPC_LR = uiaxes(imgRow); app.ui.axDPC_LR.Layout.Column = 2;
        title(app.ui.axDPC_TB, 'DPC-TB'); title(app.ui.axDPC_LR, 'DPC-LR');
        for ax = [app.ui.axDPC_TB, app.ui.axDPC_LR]
            axis(ax,'image'); axis(ax,'off'); colormap(ax, gray);
        end
        app.ui.imgDPC_TB = imagesc(app.ui.axDPC_TB, zeros(2,2));
        app.ui.imgDPC_LR = imagesc(app.ui.axDPC_LR, zeros(2,2));

        ctrlGrid = uigridlayout(g, [6 2]);
        ctrlGrid.Layout.Row = 2;
        ctrlGrid.ColumnWidth = {110, '1x'};
        ctrlGrid.RowHeight = repmat({'1x'}, 1, 6);

        l1 = uilabel(ctrlGrid, 'Text', 'Brightness'); l1.Layout.Row=1; l1.Layout.Column=1;
        app.ui.sldBrightness = uislider(ctrlGrid, 'Limits', [-0.5 0.5], 'Value', 0, ...
            'ValueChangedFcn', @dispControl_Callback);
        app.ui.sldBrightness.Layout.Row=1; app.ui.sldBrightness.Layout.Column=2;

        l2 = uilabel(ctrlGrid, 'Text', 'Contrast'); l2.Layout.Row=2; l2.Layout.Column=1;
        app.ui.sldContrast = uislider(ctrlGrid, 'Limits', [0.1 3], 'Value', 1, ...
            'ValueChangedFcn', @dispControl_Callback);
        app.ui.sldContrast.Layout.Row=2; app.ui.sldContrast.Layout.Column=2;

        l3 = uilabel(ctrlGrid, 'Text', 'Gamma'); l3.Layout.Row=3; l3.Layout.Column=1;
        app.ui.sldGamma = uislider(ctrlGrid, 'Limits', [0.2 3], 'Value', 1, ...
            'ValueChangedFcn', @dispControl_Callback);
        app.ui.sldGamma.Layout.Row=3; app.ui.sldGamma.Layout.Column=2;

        l4 = uilabel(ctrlGrid, 'Text', 'Display Min'); l4.Layout.Row=4; l4.Layout.Column=1;
        app.ui.efDispMin = uieditfield(ctrlGrid, 'numeric', 'Value', 0, 'ValueChangedFcn', @dispControl_Callback);
        app.ui.efDispMin.Layout.Row=4; app.ui.efDispMin.Layout.Column=2;

        l5 = uilabel(ctrlGrid, 'Text', 'Display Max'); l5.Layout.Row=5; l5.Layout.Column=1;
        app.ui.efDispMax = uieditfield(ctrlGrid, 'numeric', 'Value', 1, 'ValueChangedFcn', @dispControl_Callback);
        app.ui.efDispMax.Layout.Row=5; app.ui.efDispMax.Layout.Column=2;

        btnReset = uibutton(ctrlGrid, 'Text', 'Reset Display', 'ButtonPushedFcn', @btnResetDisplay_Callback);
        btnReset.Layout.Row = 6; btnReset.Layout.Column = [1 2];
    end

    function buildMeasurementPanel(parentGrid, r, c)
        p = uipanel(parentGrid, 'Title', 'Structure Measurements (full segmentation arrives in Version 2)');
        p.Layout.Row = r; p.Layout.Column = c;
        g = uigridlayout(p, [6 2]);
        mk = @(txt) uilabel(g, 'Text', txt);
        mk('Glomerulus count:'); app.ui.lblGlomCount = mk('N/A (Version 2)');
        mk('Tubule count:');     app.ui.lblTubCount  = mk('N/A (Version 2)');
        mk('Mean glomerular area:'); app.ui.lblMeanGlomArea = mk('N/A (Version 2)');
        mk('Mean phase (rad):'); app.ui.lblMeanPhase = mk('-');
        mk('Mean OPD (nm):');    app.ui.lblMeanOPD = mk('-');
        mk('Lumen ratio:');      app.ui.lblLumenRatio = mk('N/A (Version 2)');
    end

    function buildBottomTabs(parentGrid)
        tg = uitabgroup(parentGrid);
        tg.Layout.Row = 3; tg.Layout.Column = 1;

        tabProfile = uitab(tg, 'Title', 'Phase Profile');
        buildProfileTab(tabProfile);

        tabHist = uitab(tg, 'Title', 'Histogram');
        buildHistogramTab(tabHist);

        tab3D = uitab(tg, 'Title', '3D Surface');
        build3DTab(tab3D);

        tabTable = uitab(tg, 'Title', 'Table');
        buildTableTab(tabTable);
    end

    function buildProfileTab(parent)
        g = uigridlayout(parent, [2 1]);
        g.RowHeight = {40, '1x'};
        toolbar = uigridlayout(g, [1 6]);
        toolbar.Layout.Row = 1;
        b1 = uibutton(toolbar, 'Text', 'Draw ROI A', 'ButtonPushedFcn', @(~,~) drawROI_Callback('A'));
        b1.Layout.Column = 1;
        b2 = uibutton(toolbar, 'Text', 'Draw ROI B', 'ButtonPushedFcn', @(~,~) drawROI_Callback('B'));
        b2.Layout.Column = 2;
        b3 = uibutton(toolbar, 'Text', 'Compare A vs B', 'ButtonPushedFcn', @btnCompareROI_Callback);
        b3.Layout.Column = 3;
        app.ui.lblROIA = uilabel(toolbar, 'Text', 'ROI A: (none)');
        app.ui.lblROIA.Layout.Column = [4 5];
        app.ui.lblROIB = uilabel(toolbar, 'Text', 'ROI B: (none)');
        app.ui.lblROIB.Layout.Column = 6;

        app.ui.axProfile = uiaxes(g);
        app.ui.axProfile.Layout.Row = 2;
        xlabel(app.ui.axProfile, 'Distance (um)');
        ylabel(app.ui.axProfile, 'Phase (rad)');
        title(app.ui.axProfile, 'Line ROI phase / OPD profile');
    end

    function buildHistogramTab(parent)
        g = uigridlayout(parent, [2 1]);
        g.RowHeight = {36, '1x'};
        row = uigridlayout(g, [1 2]); row.Layout.Row = 1;
        l = uilabel(row, 'Text', 'Source:'); l.Layout.Column = 1;
        app.ui.ddHistSource = uidropdown(row, 'Items', {'DPC-TB','DPC-LR','Phase','OPD'}, ...
            'ValueChangedFcn', @(~,~) updateHistogram());
        app.ui.ddHistSource.Layout.Column = 2;
        app.ui.axHistogram = uiaxes(g);
        app.ui.axHistogram.Layout.Row = 2;
    end

    function build3DTab(parent)
        g = uigridlayout(parent, [2 1]);
        g.RowHeight = {36, '1x'};
        b = uibutton(g, 'Text', 'Render 3D Surface (Phase)', 'ButtonPushedFcn', @btnRender3D_Callback);
        b.Layout.Row = 1;
        app.ui.ax3D = uiaxes(g);
        app.ui.ax3D.Layout.Row = 2;
    end

    function buildTableTab(parent)
        g = uigridlayout(parent, [3 1]);
        app.ui.uitableQC = uitable(g, 'ColumnName', {'Direction','Mean','Std','Min','Max','Sat %','Sharpness'});
        app.ui.uitableQC.Layout.Row = 1;
        app.ui.uitableNorm = uitable(g, 'ColumnName', {'Direction','Method','Stat Before','Stat After','Factor'});
        app.ui.uitableNorm.Layout.Row = 2;
        app.ui.uitableROI = uitable(g, 'ColumnName', {'Metric','ROI A','ROI B','Difference (A-B)'});
        app.ui.uitableROI.Layout.Row = 3;
    end

% ===================================================================
%                       CALLBACKS - LOADING
% ===================================================================
    function btnLoad4Images_Callback(~, ~)
        dlg = uifigure('Name', 'Load Four Directional Images', 'Position', [300 300 560 260]);
        g = uigridlayout(dlg, [5 3]);
        g.ColumnWidth = {100, 100, '1x'};
        dirs = {'top','bottom','left','right'};
        titles = {'Top','Bottom','Left','Right'};
        statusLbls = gobjects(1,4);
        for k = 1:4
            l = uilabel(g, 'Text', titles{k}); l.Layout.Row = k; l.Layout.Column = 1;
            b = uibutton(g, 'Text', 'Browse...', 'ButtonPushedFcn', @(src,ev) loadOneDirection(dirs{k}, statusLbls(k)));
            b.Layout.Row = k; b.Layout.Column = 2;
            statusLbls(k) = uilabel(g, 'Text', '(not loaded)');
            statusLbls(k).Layout.Row = k; statusLbls(k).Layout.Column = 3;
        end
        btnDone = uibutton(g, 'Text', 'Done', 'ButtonPushedFcn', @(~,~) close(dlg));
        btnDone.Layout.Row = 5; btnDone.Layout.Column = [1 3];
    end

    function loadOneDirection(which, statusLbl)
        [img, dispImg, fname, imgClass] = loadDirectionalImages(['Select ' which ' image']);
        if isempty(img)
            return;
        end
        gray = convertToProcessingFormat(img);
        app.data.raw.(which) = gray;
        app.data.rawDisplay.(which) = dispImg;
        app.data.raw.([which 'Class']) = imgClass;
        if isvalid(statusLbl)
            statusLbl.Text = fname;
        end
        switch which
            case 'top';    app.ui.lblFileTop.Text    = ['Top: ' fname];
            case 'bottom'; app.ui.lblFileBottom.Text = ['Bottom: ' fname];
            case 'left';   app.ui.lblFileLeft.Text    = ['Left: ' fname];
            case 'right';  app.ui.lblFileRight.Text   = ['Right: ' fname];
        end
        refreshAllDisplays();
    end

    function btnLoadTransferFn_Callback(~, ~)
        [f, p] = uigetfile('*.mat', 'Select transfer function file (must contain Hu and Hv)');
        if isequal(f, 0); return; end
        S = load(fullfile(p, f));
        if isfield(S, 'Hu') && isfield(S, 'Hv')
            app.params.Hu = S.Hu; app.params.Hv = S.Hv;
            app.ui.lblTransferFnStatus.Text = ['Transfer functions: loaded from ' f ' (Mode A ready)'];
        else
            uialert(app.ui.fig, 'File must contain variables named Hu and Hv.', 'Invalid Transfer Function File');
        end
    end

% ===================================================================
%                       CALLBACKS - REGISTER
% ===================================================================
    function btnRegister_Callback(~, ~)
        raws = app.data.raw;
        [ok, msgs] = validateDirectionalImages(raws);
        if ~ok
            uialert(app.ui.fig, strjoin(msgs, newline), 'Cannot Register');
            return;
        end

        manualShifts = struct();
        if app.ui.cbManualShift.Value
            manualShifts.bottom = [app.ui.efShiftBottomX.Value, app.ui.efShiftBottomY.Value];
            manualShifts.left   = [app.ui.efShiftLeftX.Value,   app.ui.efShiftLeftY.Value];
            manualShifts.right  = [app.ui.efShiftRightX.Value,  app.ui.efShiftRightY.Value];
        else
            manualShifts.bottom = []; manualShifts.left = []; manualShifts.right = [];
        end

        [regImgs, shifts, warnMsgs] = registerDirectionalImages(raws.top, raws.bottom, raws.left, raws.right, ...
            manualShifts, app.params.shiftWarnPx);
        app.data.registered = regImgs;
        app.data.shifts = shifts;

        if ~app.ui.cbManualShift.Value
            app.ui.efShiftBottomX.Value = shifts.bottom(1); app.ui.efShiftBottomY.Value = shifts.bottom(2);
            app.ui.efShiftLeftX.Value   = shifts.left(1);   app.ui.efShiftLeftY.Value   = shifts.left(2);
            app.ui.efShiftRightX.Value  = shifts.right(1);  app.ui.efShiftRightY.Value  = shifts.right(2);
        end

        bitMax = struct('top', getBitDepthMax(raws.topClass, raws.top), ...
                         'bottom', getBitDepthMax(raws.bottomClass, raws.bottom), ...
                         'left', getBitDepthMax(raws.leftClass, raws.left), ...
                         'right', getBitDepthMax(raws.rightClass, raws.right));
        app.data.qc.top    = calculateQualityMetrics(raws.top, bitMax.top);
        app.data.qc.bottom = calculateQualityMetrics(raws.bottom, bitMax.bottom);
        app.data.qc.left   = calculateQualityMetrics(raws.left, bitMax.left);
        app.data.qc.right  = calculateQualityMetrics(raws.right, bitMax.right);
        updateQCTable();

        qcWarnMsgs = qualityControlWarnings(app.data.qc, app.params);
        allWarn = [warnMsgs, qcWarnMsgs];
        if ~isempty(allWarn)
            uialert(app.ui.fig, strjoin(allWarn, newline), 'Registration / Quality Warnings', 'Icon', 'warning');
        end

        app.ui.tgImages.SelectedTab = app.ui.tgImages.Children(2); % Registered tab
        refreshAllDisplays();
    end

% ===================================================================
%                       CALLBACKS - RECONSTRUCT
% ===================================================================
    function btnReconstruct_Callback(~, ~)
        reg = app.data.registered;
        if isempty(reg.top) || isempty(reg.bottom) || isempty(reg.left) || isempty(reg.right)
            uialert(app.ui.fig, 'Run "Register" first (or ensure all four registered images exist).', 'Cannot Reconstruct');
            return;
        end

        method = 'mean'; % V1 default normalization method; see normalizeDirectionalImages comments to change
        [normImgs, normFactors] = normalizeDirectionalImages(reg.top, reg.bottom, reg.left, reg.right, method, 50, []);
        app.data.normalized = normImgs;
        app.data.normFactors = normFactors;
        updateNormTable();

        app.params.epsilon = app.ui.efEpsilon.Value;
        [dpcTB, dpcLR] = calculateDPCImages(normImgs.top, normImgs.bottom, normImgs.left, normImgs.right, app.params.epsilon);
        app.data.dpcTB = dpcTB; app.data.dpcLR = dpcLR;

        app.params.regParam     = app.ui.efRegParam.Value;
        app.params.wavelength_um = app.ui.efWavelength.Value;
        app.params.illumNA      = app.ui.efIllumNA.Value;
        app.params.objNA        = app.ui.efObjNA.Value;
        app.params.pixelSize_um = app.ui.efPixelSize.Value;

        [phase, mode, info] = reconstructDPCPhase(dpcTB, dpcLR, app.params);

        if app.ui.cbBackgroundSub.Value
            phase = removePhaseBackground(phase, app.ui.ddBackgroundMethod.Value);
        end
        if app.ui.cbUnwrap.Value
            % Simple row-then-column 1-D unwrap - an approximation, not a
            % quality-guided 2-D unwrapper (e.g. Goldstein branch-cut).
            phase = unwrap(unwrap(phase, [], 1), [], 2);
        end

        app.data.phase = phase;
        app.data.phaseMode = mode;
        app.data.phaseInfo = info.description;
        app.data.opd = calculateOPD(phase, app.params.wavelength_um);
        deltaN = app.ui.efDeltaN.Value;
        if ~isnan(deltaN) && deltaN ~= 0
            app.data.thickness = calculateThickness(phase, app.params.wavelength_um, deltaN);
        else
            app.data.thickness = [];
        end

        dpcContrastWarn = {};
        if std(dpcTB(:)) < app.params.dpcContrastWarnThresh
            dpcContrastWarn{end+1} = 'Low DPC-TB contrast - check Top/Bottom illumination alignment and intensity.';
        end
        if std(dpcLR(:)) < app.params.dpcContrastWarnThresh
            dpcContrastWarn{end+1} = 'Low DPC-LR contrast - check Left/Right illumination alignment and intensity.';
        end
        if ~isempty(dpcContrastWarn)
            uialert(app.ui.fig, strjoin(dpcContrastWarn, newline), 'Quality Warning', 'Icon', 'warning');
        end

        refreshAllDisplays();
        updatePhaseDisplay();
    end

    function btnSegment_Callback(~, ~)
        uialert(app.ui.fig, sprintf(['Glomerulus / tubule / lumen segmentation, confidence scoring, and ' ...
            'manual mask correction are implemented in Version 2.\n\nVersion 1 provides the full DPC-QPI ' ...
            'processing pipeline (registration, normalization, DPC, phase reconstruction, ROI profiling, export) ' ...
            'so segmentation in V2 can operate on validated phase maps.']), 'Segmentation - Version 2', 'Icon', 'info');
    end

    function btnAbout_Callback(~, ~)
        msg = [ ...
            "QPI-based kidney tissue structural segmentation and quantitative morphology analysis." newline ...
            "This is NOT a medical diagnostic system." newline newline ...
            "Phase Mode A (calibrated) is only active when you load valid Hu/Hv transfer functions." newline ...
            "Phase Mode B (qualitative gradient-integration preview) is a display aid, not a calibrated" newline ...
            "quantitative phase map, and is always labeled as such." newline newline ...
            "Physical thickness is computed only when wavelength and delta_n are both valid." ];
        uialert(app.ui.fig, strjoin(msg, ''), 'About / Limitations', 'Icon', 'info');
    end

% ===================================================================
%                  CALLBACKS - DISPLAY-ONLY CONTROLS
% ===================================================================
    function dispControl_Callback(~, ~)
        app.disp.brightness = app.ui.sldBrightness.Value;
        app.disp.contrast   = app.ui.sldContrast.Value;
        app.disp.gamma      = app.ui.sldGamma.Value;
        app.disp.dispMin    = app.ui.efDispMin.Value;
        app.disp.dispMax    = app.ui.efDispMax.Value;
        refreshAllDisplays();
    end

    function btnResetDisplay_Callback(~, ~)
        app.ui.sldBrightness.Value = 0;
        app.ui.sldContrast.Value = 1;
        app.ui.sldGamma.Value = 1;
        allVals = [];
        for f = {'raw','registered','normalized'}
            s = app.data.(f{1});
            for d = {'top','bottom','left','right'}
                v = s.(d{1});
                if ~isempty(v); allVals = [allVals; v(:)]; end %#ok<AGROW>
            end
        end
        if ~isempty(app.data.dpcTB); allVals = [allVals; app.data.dpcTB(:); app.data.dpcLR(:)]; end
        if isempty(allVals)
            app.ui.efDispMin.Value = 0; app.ui.efDispMax.Value = 1;
        else
            app.ui.efDispMin.Value = min(allVals); app.ui.efDispMax.Value = max(allVals);
        end
        dispControl_Callback();
    end

% ===================================================================
%                     DISPLAY REFRESH FUNCTIONS
% ===================================================================
    function refreshAllDisplays()
        b = app.disp.brightness; c = app.disp.contrast; g = app.disp.gamma;
        lo = app.disp.dispMin; hi = app.disp.dispMax;

        renderQuad('raw', app.ui.axRawTop, app.ui.axRawBottom, app.ui.axRawLeft, app.ui.axRawRight, b,c,g,lo,hi);
        renderQuad('registered', app.ui.axRegTop, app.ui.axRegBottom, app.ui.axRegLeft, app.ui.axRegRight, b,c,g,lo,hi);
        renderQuad('normalized', app.ui.axNormTop, app.ui.axNormBottom, app.ui.axNormLeft, app.ui.axNormRight, b,c,g,lo,hi);

        if ~isempty(app.data.dpcTB)
            app.ui.imgDPC_TB.CData = applyDisplayLUT(app.data.dpcTB, b,c,g,lo,hi);
            app.ui.imgDPC_LR.CData = applyDisplayLUT(app.data.dpcLR, b,c,g,lo,hi);
            caxis(app.ui.axDPC_TB, [0 1]); caxis(app.ui.axDPC_LR, [0 1]);
        end
    end

    function renderQuad(field, axT, axB, axL, axR, b,c,g,lo,hi)
        s = app.data.(field);
        pairs = {axT,'top'; axB,'bottom'; axL,'left'; axR,'right'};
        for i = 1:4
            ax = pairs{i,1}; d = pairs{i,2};
            img = s.(d);
            if isempty(img)
                cla(ax);
            else
                out = applyDisplayLUT(img, b,c,g,lo,hi);
                imagesc(ax, out); axis(ax,'image'); axis(ax,'off'); colormap(ax, gray); caxis(ax, [0 1]);
            end
        end
    end

    function updatePhaseDisplay()
        if isempty(app.data.phase)
            app.ui.imgPhaseHandle.CData = zeros(2,2);
            app.ui.lblMode.Text = 'Mode: (no phase computed yet)';
            return;
        end
        app.ui.imgPhaseHandle.CData = app.data.phase;
        colormap(app.ui.axPhase, app.ui.ddColormap.Value);
        caxis(app.ui.axPhase, [app.ui.efPhaseMin.Value, app.ui.efPhaseMax.Value]);
        axis(app.ui.axPhase, 'image');

        if strcmp(app.data.phaseMode, 'A')
            app.ui.lblMode.Text = 'Mode: A - CALIBRATED (Tikhonov, user transfer functions)';
            app.ui.lblMode.FontColor = [0 0.5 0];
        else
            app.ui.lblMode.Text = 'Mode: B - QUALITATIVE PHASE PREVIEW (not calibrated)';
            app.ui.lblMode.FontColor = [0.7 0 0];
        end

        app.ui.lblMeanPhase.Text = sprintf('%.4f', mean(app.data.phase(:)));
        if ~isempty(app.data.opd)
            app.ui.lblMeanOPD.Text = sprintf('%.2f', mean(app.data.opd(:)) * 1000); % um -> nm
        end
        updateHistogram();
    end

    function updateHistogram()
        src = app.ui.ddHistSource.Value;
        switch src
            case 'DPC-TB'; data = app.data.dpcTB;
            case 'DPC-LR'; data = app.data.dpcLR;
            case 'Phase';  data = app.data.phase;
            case 'OPD';    data = app.data.opd;
        end
        cla(app.ui.axHistogram);
        if isempty(data); return; end
        histogram(app.ui.axHistogram, data(:), 60);
        title(app.ui.axHistogram, [src ' histogram']);
    end

    function btnRender3D_Callback(~, ~)
        if isempty(app.data.phase)
            uialert(app.ui.fig, 'Reconstruct a phase map first.', 'No Phase Data');
            return;
        end
        step = max(1, round(max(size(app.data.phase)) / 200));
        Z = app.data.phase(1:step:end, 1:step:end);
        cla(app.ui.ax3D);
        surf(app.ui.ax3D, Z, 'EdgeColor', 'none');
        colormap(app.ui.ax3D, app.ui.ddColormap.Value);
        xlabel(app.ui.ax3D, 'x (px, downsampled)'); ylabel(app.ui.ax3D, 'y (px, downsampled)'); zlabel(app.ui.ax3D, 'Phase (rad)');
        title(app.ui.ax3D, sprintf('Phase surface (Mode %s)', app.data.phaseMode));
    end

% ===================================================================
%                 MOUSE READOUT (Section 8: phase / OPD / thickness)
% ===================================================================
    function onMouseMove(~, ~)
        if isempty(app.data.phase); return; end
        cp = app.ui.axPhase.CurrentPoint;
        pt = cp(1, 1:2);
        xl = app.ui.axPhase.XLim; yl = app.ui.axPhase.YLim;
        if pt(1) < xl(1) || pt(1) > xl(2) || pt(2) < yl(1) || pt(2) > yl(2)
            return;
        end
        updateReadout(round(pt(1)), round(pt(2)));
    end

    function onImagePhaseClicked(~, event)
        if isempty(app.data.phase); return; end
        if isprop(event, 'IntersectionPoint')
            pt = event.IntersectionPoint;
        else
            cp = app.ui.axPhase.CurrentPoint; pt = cp(1,1:2);
        end
        col = round(pt(1)); row = round(pt(2));
        app.data.lastClick = [col, row];
        updateReadout(col, row);
    end

    function updateReadout(col, row)
        [ny, nx] = size(app.data.phase);
        if col < 1 || col > nx || row < 1 || row > ny; return; end
        ph = app.data.phase(row, col);
        opdVal = calculateOPD(ph, app.params.wavelength_um);
        deltaN = app.ui.efDeltaN.Value;
        if ~isnan(deltaN) && deltaN ~= 0
            thickVal = calculateThickness(ph, app.params.wavelength_um, deltaN);
            thickStr = sprintf('%.4f um', thickVal);
        else
            thickStr = '(enter delta_n)';
        end
        app.ui.lblReadout.Text = sprintf('X: %d   Y: %d   Phase: %.4f rad   OPD: %.4f um   Thickness: %s', ...
            col, row, ph, opdVal, thickStr);
    end

% ===================================================================
%                        ROI TOOLS (Section 9)
% ===================================================================
    function drawROI_Callback(slot)
        if isempty(app.data.phase)
            uialert(app.ui.fig, 'Reconstruct a phase map first.', 'No Phase Data');
            return;
        end
        shape = uiconfirm(app.ui.fig, 'Select ROI type:', ['Draw ROI ' slot], ...
            'Options', {'Point','Line','Rectangle','Polygon','Cancel'}, ...
            'DefaultOption', 5, 'CancelOption', 5);
        if strcmp(shape, 'Cancel'); return; end

        roi = struct('shape', shape, 'mask', [], 'lineXY', []);
        switch shape
            case 'Point'
                h = drawpoint(app.ui.axPhase); wait(h);
                roi.mask = false(size(app.data.phase));
                p = round(h.Position);
                if p(2) >= 1 && p(2) <= size(roi.mask,1) && p(1) >= 1 && p(1) <= size(roi.mask,2)
                    roi.mask(p(2), p(1)) = true;
                end
            case 'Line'
                h = drawline(app.ui.axPhase); wait(h);
                roi.lineXY = h.Position;
                roi.mask = false(size(app.data.phase));
            case 'Rectangle'
                h = drawrectangle(app.ui.axPhase); wait(h);
                roi.mask = createMask(h);
            case 'Polygon'
                h = drawpolygon(app.ui.axPhase); wait(h);
                roi.mask = createMask(h);
        end

        if strcmp(shape, 'Line')
            [distUm, phaseProfile, opdProfile] = createPhaseProfile(app.data.phase, app.data.opd, ...
                roi.lineXY, app.params.pixelSize_um);
            roi.distUm = distUm; roi.phaseProfile = phaseProfile; roi.opdProfile = opdProfile;
            plotProfile(slot, distUm, phaseProfile, opdProfile);
            % Populate the mask from the sampled line pixels so the summary
            % stats below (mean/median/std/min/max) reflect the line, not
            % an empty region - the profile plot alone does not feed those.
            [ny, nx] = size(roi.mask);
            x = roi.lineXY(:,1); y = roi.lineXY(:,2);
            [cx, cy] = improfile(app.data.phase, x, y);
            rows = round(cy); cols = round(cx);
            valid = rows >= 1 & rows <= ny & cols >= 1 & cols <= nx;
            idx = sub2ind([ny, nx], rows(valid), cols(valid));
            roi.mask(idx) = true;
        end

        deltaN = app.ui.efDeltaN.Value;
        if isnan(deltaN); deltaN = 0; end
        stats = analyzePhaseROI(app.data.phase, app.data.opd, app.data.thickness, roi.mask, deltaN);
        roi.stats = stats;

        if strcmp(slot, 'A')
            app.data.roiA = roi;
            app.ui.lblROIA.Text = sprintf('ROI A (%s): mean=%.3f rad', shape, stats.meanPhase);
        else
            app.data.roiB = roi;
            app.ui.lblROIB.Text = sprintf('ROI B (%s): mean=%.3f rad', shape, stats.meanPhase);
        end
        updateROITable();
    end

    function plotProfile(slot, distUm, phaseProfile, opdProfile)
        cla(app.ui.axProfile);
        yyaxis(app.ui.axProfile, 'left');
        plot(app.ui.axProfile, distUm, phaseProfile, '-', 'DisplayName', ['ROI ' slot ' phase']);
        ylabel(app.ui.axProfile, 'Phase (rad)');
        yyaxis(app.ui.axProfile, 'right');
        plot(app.ui.axProfile, distUm, opdProfile, '--', 'DisplayName', ['ROI ' slot ' OPD']);
        ylabel(app.ui.axProfile, 'OPD (um)');
        xlabel(app.ui.axProfile, 'Distance (um)');
        legend(app.ui.axProfile, 'show');
        title(app.ui.axProfile, ['Line ROI ' slot ' profile']);
    end

    function btnCompareROI_Callback(~, ~)
        if isempty(app.data.roiA) || isempty(app.data.roiB)
            uialert(app.ui.fig, 'Draw both ROI A and ROI B first.', 'Cannot Compare');
            return;
        end
        updateROITable();
    end

% ===================================================================
%                       TABLE UPDATE FUNCTIONS
% ===================================================================
    function updateQCTable()
        qc = app.data.qc;
        dirs = {'top','bottom','left','right'};
        rows = cell(4,7);
        for i = 1:4
            d = dirs{i};
            if isfield(qc, d) && ~isempty(qc.(d))
                m = qc.(d);
                rows(i,:) = {d, m.meanVal, m.stdVal, m.minVal, m.maxVal, m.satPercent, m.sharpness};
            else
                rows(i,:) = {d, NaN, NaN, NaN, NaN, NaN, NaN};
            end
        end
        app.ui.uitableQC.Data = rows;
    end

    function updateNormTable()
        nf = app.data.normFactors;
        dirs = {'top','bottom','left','right'};
        rows = cell(4,5);
        for i = 1:4
            d = dirs{i};
            if isfield(nf, d)
                m = nf.(d);
                rows(i,:) = {d, m.method, m.statBefore, m.statAfter, m.factor};
            else
                rows(i,:) = {d, '-', NaN, NaN, NaN};
            end
        end
        app.ui.uitableNorm.Data = rows;
    end

    function updateROITable()
        a = app.data.roiA; b = app.data.roiB;
        metrics = {'Mean phase (rad)','Median phase (rad)','Std phase (rad)','Min phase (rad)', ...
            'Max phase (rad)','Mean OPD (um)','Est. thickness (um)'};
        rows = cell(numel(metrics), 4);
        for i = 1:numel(metrics)
            rows{i,1} = metrics{i};
            rows{i,2} = getStatOrNaN(a, i);
            rows{i,3} = getStatOrNaN(b, i);
            if ~isnan(rows{i,2}) && ~isnan(rows{i,3})
                rows{i,4} = rows{i,2} - rows{i,3};
            else
                rows{i,4} = NaN;
            end
        end
        app.ui.uitableROI.Data = rows;
    end

    function v = getStatOrNaN(roi, idx)
        if isempty(roi) || ~isfield(roi, 'stats')
            v = NaN; return;
        end
        s = roi.stats;
        fields = {'meanPhase','medianPhase','stdPhase','minPhase','maxPhase','meanOPD','thickness'};
        v = s.(fields{idx});
    end

% ===================================================================
%                          EXPORT (Section 13)
% ===================================================================
    function btnExport_Callback(~, ~)
        outDir = uigetdir(pwd, 'Select export folder');
        if isequal(outDir, 0); return; end
        bundle.data = app.data;
        bundle.params = app.params;
        bundle.disp = app.disp;
        exportAnalysisResults(bundle, outDir);
        uialert(app.ui.fig, ['Export complete:' newline outDir], 'Export', 'Icon', 'success');
    end

    app.ui.fig.WindowButtonMotionFcn = @onMouseMove;

end % ======================= END OF dpcQPIApp =============================


%% ========================================================================
%  DEFAULT PARAMETERS
%  ========================================================================
function params = defaultParams()
% DEFAULTPARAMS  Central place for every physical / processing parameter.
% wavelength_um / illumNA / objNA / pixelSize_um are recorded for
% documentation and OPD/thickness math; illumNA/objNA are NOT used to
% synthesize DPC transfer functions internally (see reconstructDPCPhase).
params.wavelength_um = 0.532;   % [SET FIRST] illumination center wavelength, micrometers
params.illumNA       = 0.30;    % illumination NA (recorded only, see reconstructDPCPhase)
params.objNA         = 0.50;    % objective NA (recorded only, see reconstructDPCPhase)
params.pixelSize_um  = 1.0;     % [SET FIRST] effective sample-plane pixel size, micrometers
params.regParam      = 1e-2;    % [TUNE FIRST] Tikhonov regularization for phase reconstruction
params.epsilon       = 1e-3;    % [TUNE FIRST] DPC ratio denominator epsilon (avoid divide-by-zero).
                                 % NOTE: scale this to your images' actual intensity range - e.g.
                                 % ~1e-3 is reasonable if inputs are pre-scaled to about [0,1], but
                                 % for raw 16-bit-scale data (means in the thousands) use a
                                 % correspondingly larger epsilon (e.g. 1-10) or it will have no effect.
params.shiftWarnPx   = 50;      % warn if a registration shift exceeds this many pixels
params.brightnessMismatchFrac = 0.3; % warn if a direction's mean differs from group mean by this fraction
params.satWarnFrac   = 0.02;    % warn if saturated-pixel fraction exceeds this
params.dpcContrastWarnThresh = 0.01; % warn if DPC std is below this (low contrast)
params.Hu = []; params.Hv = []; % calibrated transfer functions (Mode A), empty => Mode B
end


%% ========================================================================
%  2. IMAGE INPUT
%  ========================================================================
function [img, dispImg, fname, imgClass] = loadDirectionalImages(promptTitle)
% LOADDIRECTIONALIMAGES  Prompts the user for one image file (png/tif/jpg/
% bmp/mat). Returns the loaded array (native class, for display) plus a
% display copy (kept in original color if RGB) and the class name (used
% later to determine bit-depth for saturation checks).
img = []; dispImg = []; fname = ''; imgClass = '';
[f, p] = uigetfile({'*.png;*.tif;*.tiff;*.jpg;*.jpeg;*.bmp;*.mat', ...
    'Supported Files (*.png,*.tif,*.tiff,*.jpg,*.bmp,*.mat)'}, promptTitle);
if isequal(f, 0); return; end
fp = fullfile(p, f);
[~, nm, ext] = fileparts(fp);
try
    if strcmpi(ext, '.mat')
        S = load(fp);
        vn = fieldnames(S);
        isCandidate = structfun(@(v) isnumeric(v) && ismatrix(v) && numel(v) > 100, S);
        numericVars = vn(isCandidate);
        if isempty(numericVars)
            warning('No suitable numeric variable found in %s.', fp); return;
        elseif numel(numericVars) == 1
            sel = numericVars{1};
        else
            [idx, ok] = listdlg('ListString', numericVars, 'SelectionMode', 'single', ...
                'PromptString', sprintf('Select image variable in %s:', [nm ext]));
            if ~ok; return; end
            sel = numericVars{idx};
        end
        img = S.(sel);
    else
        img = imread(fp);
    end
catch ME
    warning('Failed to load %s: %s', fp, ME.message);
    return;
end
dispImg = img;
imgClass = class(img);
fname = [nm ext];
end


function gray = convertToProcessingFormat(img)
% CONVERTTOPROCESSINGFORMAT  Converts a loaded image (grayscale or RGB,
% any numeric class) to double-precision grayscale for all downstream
% calculations. WHY: registration/normalization/DPC math require a single
% floating-point channel per direction; RGB inputs are converted (the
% color original is kept separately in app.data.rawDisplay for display).
if size(img, 3) == 3
    gray = double(rgb2gray(img));
else
    gray = double(img(:,:,1));
end
end


function bitMax = getBitDepthMax(imgClass, img)
% GETBITDEPTHMAX  Determines the reference "full scale" value used for
% saturation-percentage QC checks, based on the original file's numeric
% class (uint8/uint16 have a known fixed max; other classes fall back to
% the image's own observed max as a best estimate).
switch imgClass
    case 'uint8';  bitMax = 255;
    case 'uint16'; bitMax = 65535;
    otherwise
        if isempty(img); bitMax = 1; else; bitMax = max(img(:)); end
end
end


function [ok, msgs] = validateDirectionalImages(raws)
% VALIDATEDIRECTIONALIMAGES  Checks that all four directional images are
% present, non-empty, and share identical dimensions. WHY: registration/
% DPC math is pixel-wise and silently produces garbage if sizes mismatch.
ok = true; msgs = {};
dirs = {'top','bottom','left','right'};
for i = 1:4
    if isempty(raws.(dirs{i}))
        msgs{end+1} = sprintf('%s image is missing.', dirs{i}); %#ok<AGROW>
        ok = false;
    end
end
if ~ok; return; end

sz = size(raws.top);
for i = 2:4
    if ~isequal(size(raws.(dirs{i})), sz)
        msgs{end+1} = sprintf('%s image size %s does not match Top image size %s.', ...
            dirs{i}, mat2str(size(raws.(dirs{i}))), mat2str(sz)); %#ok<AGROW>
        ok = false;
    end
end

means = [mean(raws.top(:)), mean(raws.bottom(:)), mean(raws.left(:)), mean(raws.right(:))];
groupMean = mean(means);
for i = 1:4
    if groupMean > 0 && abs(means(i) - groupMean) / groupMean > 0.5
        msgs{end+1} = sprintf('%s mean intensity (%.2f) differs substantially from group mean (%.2f).', ...
            dirs{i}, means(i), groupMean); %#ok<AGROW>
    end
end
end


%% ========================================================================
%  QUALITY CONTROL (Section 12)
%  ========================================================================
function qc = calculateQualityMetrics(img, bitMax)
% CALCULATEQUALITYMETRICS  Basic per-image statistics used both to warn
% the user before reconstruction and to populate the QC table.
qc.meanVal = mean(img(:));
qc.stdVal  = std(img(:));
qc.minVal  = min(img(:));
qc.maxVal  = max(img(:));
qc.satPercent = 100 * nnz(img >= 0.98 * bitMax) / numel(img);
qc.sharpness = computeSharpnessScore(img);
end


function sharpness = computeSharpnessScore(img)
% COMPUTESHARPNESSSCORE  Laplacian-variance blur metric: sharper images
% have higher local second-derivative variance. Only meaningful compared
% RELATIVELY across the four directions of the same acquisition (not as
% an absolute universal threshold), since scale depends on illumination.
h = fspecial('laplacian', 0.2);
lapImg = imfilter(img, h, 'replicate');
sharpness = var(lapImg(:));
end


function msgs = qualityControlWarnings(qc, params)
% QUALITYCONTROLWARNINGS  Turns calculateQualityMetrics() output into
% human-readable warnings for saturation and relative blur, per Section 12.
msgs = {};
dirs = {'top','bottom','left','right'};
sharpVals = zeros(1,4);
for i = 1:4
    d = dirs{i};
    if ~isfield(qc, d) || isempty(qc.(d)); continue; end
    m = qc.(d);
    if m.satPercent > 100 * 0.02
        msgs{end+1} = sprintf('%s: %.1f%% saturated pixels (threshold %.1f%%).', d, m.satPercent, 100*0.02); %#ok<AGROW>
    end
    sharpVals(i) = m.sharpness;
end
maxSharp = max(sharpVals);
if maxSharp > 0
    for i = 1:4
        if sharpVals(i) < 0.2 * maxSharp
            msgs{end+1} = sprintf('%s appears comparatively blurry (sharpness %.3g vs max %.3g).', ...
                dirs{i}, sharpVals(i), maxSharp); %#ok<AGROW>
        end
    end
end
end


%% ========================================================================
%  4. REGISTRATION
%  ========================================================================
function [regImgs, shifts, warnMsgs] = registerDirectionalImages(top, bottom, left, right, manualShifts, shiftWarnPx)
% REGISTERDIRECTIONALIMAGES  Translation-only registration of Bottom/Left/
% Right onto Top (the reference) using phase-correlation (imregcorr,
% transformType='translation'). WHY: the four directional images are
% acquired from slightly different illumination angles and mechanical
% paths, which typically introduces only a small pixel shift (not
% rotation/scale) between them - translation registration is the
% appropriate first-order correction and keeps image size unchanged.
warnMsgs = {};
regImgs = struct('top', top, 'bottom', [], 'left', [], 'right', []);
shifts = struct('bottom', [0 0], 'left', [0 0], 'right', [0 0]);

refView = imref2d(size(top));
dirs = {'bottom','left','right'};
movs = {bottom, left, right};

for i = 1:3
    d = dirs{i};
    mov = movs{i};
    if ~isempty(manualShifts.(d))
        dx = manualShifts.(d)(1); dy = manualShifts.(d)(2);
        regImgs.(d) = imtranslate(mov, [dx, dy], 'OutputView', 'same');
    else
        try
            tform = imregcorr(mov, top, 'translation');
            [dx, dy] = tformTranslation(tform);
            regImgs.(d) = imwarp(mov, tform, 'OutputView', refView);
        catch ME
            warnMsgs{end+1} = sprintf('Registration failed for %s (%s) - using unregistered image.', d, ME.message); %#ok<AGROW>
            dx = 0; dy = 0;
            regImgs.(d) = mov;
        end
    end
    shifts.(d) = [dx, dy];
    if abs(dx) > shiftWarnPx || abs(dy) > shiftWarnPx
        warnMsgs{end+1} = sprintf('%s registration shift is large: dx=%.1f, dy=%.1f px (warn threshold %d px).', ...
            d, dx, dy, shiftWarnPx); %#ok<AGROW>
    end
end
end


function [dx, dy] = tformTranslation(tform)
% TFORMTRANSLATION  Extracts [dx dy] pixel translation from either the
% legacy affine2d (property T) or newer affinetform2d (property A) output
% of imregcorr, so this code works across MATLAB releases.
if isprop(tform, 'Translation')
    t = tform.Translation; dx = t(1); dy = t(2);
elseif isprop(tform, 'T')
    dx = tform.T(3,1); dy = tform.T(3,2);
else
    A = tform.A; dx = A(1,3); dy = A(2,3);
end
end


%% ========================================================================
%  5. NORMALIZATION
%  ========================================================================
function [normImgs, normFactors] = normalizeDirectionalImages(top, bottom, left, right, method, prctileVal, flatField)
% NORMALIZEDIRECTIONALIMAGES  Scales each REGISTERED directional image
% SEPARATELY so that a chosen intensity statistic (mean/median/percentile)
% matches the common target (the average of that statistic across all
% four directions). WHY: illumination-direction brightness differences
% are a systematic multiplicative offset that must be corrected before
% computing DPC ratios - but the four images must remain four SEPARATE
% arrays (never averaged into one) so spatial structure is preserved.
% If flatField is supplied (a background/flat image, same size), each
% image is first divided by it (classic flat-field correction) before
% the statistic-matching scale factor is computed.
dirs = {'top','bottom','left','right'};
imgs = {top, bottom, left, right};

if ~isempty(flatField)
    ff = flatField / mean(flatField(:));
    for i = 1:4; imgs{i} = imgs{i} ./ (ff + eps); end
end

stats = zeros(1,4);
for i = 1:4
    stats(i) = imageStatistic(imgs{i}, method, prctileVal);
end
target = mean(stats);

normImgs = struct();
normFactors = struct();
for i = 1:4
    d = dirs{i};
    factor = target / (stats(i) + eps);
    normImgs.(d) = imgs{i} * factor;
    normFactors.(d) = struct('method', method, 'statBefore', stats(i), 'statAfter', target, 'factor', factor);
end
end


function v = imageStatistic(img, method, prctileVal)
% IMAGESTATISTIC  Single-number summary of an image used for normalization.
switch lower(method)
    case 'mean';   v = mean(img(:));
    case 'median';  v = median(img(:));
    case 'percentile'; v = prctile(img(:), prctileVal);
    otherwise; v = mean(img(:));
end
end


%% ========================================================================
%  6. DPC IMAGE CALCULATION
%  ========================================================================
function [dpcTB, dpcLR] = calculateDPCImages(topNorm, bottomNorm, leftNorm, rightNorm, epsilon)
% CALCULATEDPCIMAGES  DPC_TB = (Top-Bottom)/(Top+Bottom+eps); DPC_LR
% analogous for Left/Right. These are QUANTITATIVE intensity-asymmetry
% maps (not yet phase) - phase is only obtained via reconstructDPCPhase.
dpcTB = (topNorm - bottomNorm) ./ (topNorm + bottomNorm + epsilon);
dpcLR = (leftNorm - rightNorm) ./ (leftNorm + rightNorm + epsilon);
end


%% ========================================================================
%  7. PHASE RECONSTRUCTION
%  ========================================================================
function [phase, mode, info] = reconstructDPCPhase(dpcTB, dpcLR, params)
% RECONSTRUCTDPCPHASE  Two modes, selected automatically:
%
% MODE A (CALIBRATED, QUANTITATIVE): active only when params.Hu and
% params.Hv (precomputed DPC phase transfer functions, same size as
% dpcTB/dpcLR) are supplied. Combines them via the standard linear-inverse
% Tikhonov-regularized deconvolution used in DPC phase retrieval
% (Tian & Waller, Optics Express 2015):
%   phase = IFFT[ (Hu*.*FFT(dpcTB) + Hv*.*FFT(dpcLR)) ./ (|Hu|^2+|Hv|^2+reg) ]
% This function deliberately does NOT synthesize Hu/Hv from wavelength/
% NA internally: a physically correct DPC weak-object transfer function
% depends on the exact illumination source shape and partial-coherence
% imaging model, and an incorrect in-code guess would silently produce a
% wrong "phase" map. Supply Hu/Hv from your own validated optical model
% (or published/calibrated source) via the "Load Transfer Functions" button.
%
% MODE B (QUALITATIVE PREVIEW): used whenever valid Hu/Hv are not
% available. Treats dpcTB/dpcLR as proportional to vertical/horizontal
% phase-gradient-like signals and integrates them with the Frankot-
% Chellappa Fourier least-squares gradient integration - a standard,
% well-defined technique, but the result is a QUALITATIVE PHASE PREVIEW,
% not a calibrated quantitative phase map, and is always labeled as such
% in the GUI.

hasTF = isfield(params, 'Hu') && isfield(params, 'Hv') && ~isempty(params.Hu) && ~isempty(params.Hv) ...
    && isequal(size(params.Hu), size(dpcTB)) && isequal(size(params.Hv), size(dpcLR));

if hasTF
    mode = 'A';
    Fu = fft2(dpcTB); Fv = fft2(dpcLR);
    Hu = params.Hu; Hv = params.Hv;
    numerator = conj(Hu) .* Fu + conj(Hv) .* Fv;
    denominator = abs(Hu).^2 + abs(Hv).^2 + params.regParam;
    phaseF = numerator ./ denominator;
    phase = real(ifft2(phaseF));
    info.description = 'Calibrated Tikhonov-regularized DPC phase reconstruction using user-supplied transfer functions.';
else
    mode = 'B';
    [phase, info] = integratePhaseGradientQualitatively(dpcTB, dpcLR, params.regParam);
end
end


function [surfaceOut, info] = integratePhaseGradientQualitatively(gx, gy, regParam)
% INTEGRATEPHASEGRADIENTQUALITATIVELY  Frankot-Chellappa Fourier gradient
% integration: reconstructs a surface whose gradients best match (gx,gy)
% in a least-squares sense. Standard, well-defined math - but gx/gy here
% are DPC contrast ratios, not verified physical gradients, so the output
% is a QUALITATIVE PHASE PREVIEW only, never a calibrated quantitative
% phase map.
[ny, nx] = size(gx);
[u, v] = meshgrid((0:nx-1) - floor(nx/2), (0:ny-1) - floor(ny/2));
u = ifftshift(u) * 2 * pi / nx;
v = ifftshift(v) * 2 * pi / ny;
Fx = fft2(gx); Fy = fft2(gy);
denom = (u.^2 + v.^2 + regParam);
Z = (-1i * u .* Fx - 1i * v .* Fy) ./ denom;
Z(1,1) = 0;
surfaceOut = real(ifft2(Z));
info.description = 'Qualitative phase preview via Frankot-Chellappa Fourier gradient integration. NOT a calibrated quantitative phase map.';
end


function phaseOut = removePhaseBackground(phase, method)
% REMOVEPHASEBACKGROUND  Subtracts an estimated background phase offset.
% 'mean': subtracts the whole-image mean (assumes most of the FOV is
% approximately flat/background). 'corners': subtracts the mean of small
% patches at the four image corners (assumes tissue is centered and
% corners are background) - usually a better estimate for tissue samples.
switch lower(method)
    case 'corners'
        [ny, nx] = size(phase);
        s = max(1, round(0.05 * min(ny,nx)));
        corners = [phase(1:s,1:s); phase(1:s,end-s+1:end); phase(end-s+1:end,1:s); phase(end-s+1:end,end-s+1:end)];
        bg = mean(corners(:));
    otherwise
        bg = mean(phase(:));
end
phaseOut = phase - bg;
end


%% ========================================================================
%  8. PHASE VALUE, OPD, AND THICKNESS
%  ========================================================================
function opd = calculateOPD(phase, wavelength_um)
% CALCULATEOPD  OPD = wavelength * phase / (2*pi). QUANTITATIVE only to
% the extent the input phase is (i.e. valid under Mode A; treat as
% qualitative under Mode B).
opd = wavelength_um .* phase ./ (2 * pi);
end


function thickness = calculateThickness(phase, wavelength_um, deltaN)
% CALCULATETHICKNESS  Thickness = wavelength*phase/(2*pi*delta_n). Only
% call this with a real, non-zero delta_n - callers in this file check
% that before invoking it. Always an ESTIMATE dependent on the user-
% supplied delta_n.
thickness = wavelength_um .* phase ./ (2 * pi * deltaN);
end


%% ========================================================================
%  9. ROI PHASE PROFILER
%  ========================================================================
function stats = analyzePhaseROI(phase, opd, thickness, roiMask, deltaN)
% ANALYZEPHASEROI  Mean/median/std/min/max phase and mean OPD (and
% thickness, if delta_n is valid) within an ROI mask.
vals = phase(roiMask);
if isempty(vals)
    stats = struct('meanPhase', NaN, 'medianPhase', NaN, 'stdPhase', NaN, ...
        'minPhase', NaN, 'maxPhase', NaN, 'meanOPD', NaN, 'thickness', NaN);
    return;
end
stats.meanPhase = mean(vals);
stats.medianPhase = median(vals);
stats.stdPhase = std(vals);
stats.minPhase = min(vals);
stats.maxPhase = max(vals);
if ~isempty(opd)
    stats.meanOPD = mean(opd(roiMask));
else
    stats.meanOPD = NaN;
end
if ~isempty(thickness) && deltaN ~= 0
    stats.thickness = mean(thickness(roiMask));
else
    stats.thickness = NaN;
end
end


function [distUm, phaseProfile, opdProfile] = createPhaseProfile(phase, opd, lineXY, pixelSize_um)
% CREATEPHASEPROFILE  Samples phase/OPD along a user-drawn line ROI
% (lineXY = [x1 y1; x2 y2], as returned by drawline's .Position), using
% improfile, and converts pixel distance to micrometers.
x = lineXY(:,1); y = lineXY(:,2);
[cx, cy, phaseProfile] = improfile(phase, x, y);
if ~isempty(opd)
    [~, ~, opdProfile] = improfile(opd, x, y);
else
    opdProfile = nan(size(phaseProfile));
end
d = [0; cumsum(hypot(diff(cx), diff(cy)))];
distUm = d * pixelSize_um;
end


%% ========================================================================
%  13. EXPORT
%  ========================================================================
function exportAnalysisResults(bundle, outDir)
% EXPORTANALYSISRESULTS  Saves registered/normalized images, DPC-TB/LR,
% the reconstructed phase map (MAT + TIFF), ROI profile/histogram/3D
% figures if present, measurement tables (CSV), processing parameters,
% and a combined project MAT file, all into outDir.
if ~exist(outDir, 'dir'); mkdir(outDir); end
d = bundle.data;

saveDirImages(d.registered, outDir, 'registered');
saveDirImages(d.normalized, outDir, 'normalized');

if ~isempty(d.dpcTB)
    imwrite(mat2gray(d.dpcTB), fullfile(outDir, 'DPC_TB.png'));
    imwrite(mat2gray(d.dpcLR), fullfile(outDir, 'DPC_LR.png'));
    save(fullfile(outDir, 'DPC_images.mat'), '-struct', 'd', 'dpcTB', 'dpcLR');
end

if ~isempty(d.phase)
    phase = d.phase; %#ok<NASGU>
    save(fullfile(outDir, 'phase_map.mat'), 'phase');
    imwrite(mat2gray(d.phase), fullfile(outDir, 'phase_map.tiff'));
end

if isfield(d, 'qc') && ~isempty(fieldnames(d.qc))
    writetable(qcStructToTable(d.qc), fullfile(outDir, 'quality_control.csv'));
end
if isfield(d, 'normFactors') && ~isempty(fieldnames(d.normFactors))
    writetable(normStructToTable(d.normFactors), fullfile(outDir, 'normalization_factors.csv'));
end

params = bundle.params; %#ok<NASGU>
save(fullfile(outDir, 'processing_parameters.mat'), 'params');

save(fullfile(outDir, 'project.mat'), 'bundle');
end


function saveDirImages(s, outDir, label)
% SAVEDIRIMAGES  Helper for exportAnalysisResults: writes each of the
% four directional images (if present) as a TIFF and appends them to a
% single MAT file, tagged with label ('registered'/'normalized').
dirs = {'top','bottom','left','right'};
any_ = false;
for i = 1:4
    d = dirs{i};
    if isfield(s, d) && ~isempty(s.(d))
        imwrite(mat2gray(s.(d)), fullfile(outDir, sprintf('%s_%s.tiff', label, d)));
        any_ = true;
    end
end
if any_
    save(fullfile(outDir, sprintf('%s_images.mat', label)), '-struct', 's');
end
end


function T = qcStructToTable(qc)
dirs = {'top','bottom','left','right'};
rows = {};
for i = 1:4
    d = dirs{i};
    if isfield(qc, d) && ~isempty(qc.(d))
        m = qc.(d);
        rows(end+1,:) = {d, m.meanVal, m.stdVal, m.minVal, m.maxVal, m.satPercent, m.sharpness}; %#ok<AGROW>
    end
end
T = cell2table(rows, 'VariableNames', {'Direction','Mean','Std','Min','Max','SatPercent','Sharpness'});
end


function T = normStructToTable(nf)
dirs = {'top','bottom','left','right'};
rows = {};
for i = 1:4
    d = dirs{i};
    if isfield(nf, d)
        m = nf.(d);
        rows(end+1,:) = {d, m.method, m.statBefore, m.statAfter, m.factor}; %#ok<AGROW>
    end
end
T = cell2table(rows, 'VariableNames', {'Direction','Method','StatBefore','StatAfter','Factor'});
end


%% ========================================================================
%  DISPLAY-ONLY LUT (Section 3 - never modifies processing data)
%  ========================================================================
function out = applyDisplayLUT(img, brightness, contrast, gamma, dispMin, dispMax)
% APPLYDISPLAYLUT  Pure visualization remap: windows img to [dispMin,
% dispMax], applies brightness offset and contrast scaling around mid-
% gray, then gamma. Returns a NEW array for rendering only - the caller's
% original data (raw/registered/normalized/DPC/phase) is never touched.
if dispMax <= dispMin; dispMax = dispMin + eps; end
x = (img - dispMin) / (dispMax - dispMin);
x = x + brightness;
x = (x - 0.5) * contrast + 0.5;
x = max(min(x, 1), 0);
gammaSafe = max(gamma, 0.01);
out = x .^ (1 / gammaSafe);
out = max(min(out, 1), 0);
end
