function dpcQPIApp()
%DPCQPIAPP  Simplified four-direction DPC-QPI kidney tissue analysis GUI.
%
% Pipeline: load Top/Bottom/Left/Right images -> register (silent,
% automatic) -> normalize (shown, four SEPARATE images) -> DPC-TB / DPC-LR
% -> reconstruct ONE combined phase map -> classical segmentation of that
% combined map -> overlay + compact measurement summary. DPC-TB, DPC-LR,
% a DPC histogram, and the DPC contrast range are shown alongside.
%
% This is a deliberately narrow tool (by request) - no ROI profiler, no
% mouse-readout, no OPD/thickness, no display-only brightness/contrast
% sliders, no manual registration override, no multi-tab dashboard.
%
% ------------------------------------------------------------------
% REQUIRED WORDING / LIMITATION
% ------------------------------------------------------------------
% This program performs "QPI-based kidney tissue structural segmentation
% and quantitative morphology analysis." It is NOT a medical diagnostic
% system. The combined phase map is produced by qualitative Fourier
% gradient integration (Frankot-Chellappa) unless you supply calibrated
% Hu/Hv transfer functions in code (see reconstructDPCPhase) - it is
% labeled "Combined Phase Map (Qualitative)" whenever uncalibrated.
% Segmentation is classical image processing (no trained model); regions
% the algorithm cannot classify with reasonable confidence are labeled
% "Uncertain" (magenta) rather than guessed as glomerulus/tubule.
%
% ------------------------------------------------------------------
% REQUIRED MATLAB TOOLBOXES
% ------------------------------------------------------------------
%   - MATLAB (base)
%   - Image Processing Toolbox (REQUIRED): imregcorr, imwarp, imref2d,
%     stdfilt, imreconstruct, watershed, imextendedmin/imimposemin,
%     regionprops, bwconncomp, bwareaopen, bwdist, graythresh, imbinarize,
%     imopen/imclose/imfill/imerode/imdilate, strel, imread.
%
% ------------------------------------------------------------------
% HOW TO RUN
% ------------------------------------------------------------------
%   dpcQPIApp
%   -> "Load 4 Images" (Top/Bottom/Left/Right) -> set pixel size (um) if
%   known -> "Process" -> inspect Normalized / Combined+Segmentation /
%   DPC panels -> "Export".

close all force; clc;

app = struct();
app.params = defaultParams();

app.data = struct();
app.data.raw        = emptyDirStruct();
app.data.registered  = emptyDirStruct();
app.data.normalized  = emptyDirStruct();
app.data.dpcTB = []; app.data.dpcLR = [];
app.data.phase = []; app.data.phaseMode = 'B';
app.data.tissueMask = []; app.data.glomLabels = []; app.data.tubuleLabels = [];
app.data.lumenLabels = []; app.data.uncertainMask = [];
app.data.glomTable = table(); app.data.tubTable = table();
app.data.overlay = [];

app.ui = struct();
buildUI();

% ===================================================================
    function s = emptyDirStruct()
        s = struct('top', [], 'bottom', [], 'left', [], 'right', []);
    end

% ===================================================================
%                              UI BUILD
% ===================================================================
    function buildUI()
        app.ui.fig = uifigure('Name', 'DPC-QPI Kidney Analysis (Simplified)', ...
            'Position', [60 60 1500 820]);

        mainGrid = uigridlayout(app.ui.fig, [2 1]);
        mainGrid.RowHeight = {56, '1x'};

        buildToolbar(mainGrid);

        centerGrid = uigridlayout(mainGrid, [1 3]);
        centerGrid.Layout.Row = 2;
        centerGrid.ColumnWidth = {'0.9x', '1.6x', '0.9x'};

        buildNormalizedPanel(centerGrid);
        buildCombinedPanel(centerGrid);
        buildDPCPanel(centerGrid);
    end

    function buildToolbar(parentGrid)
        p = uipanel(parentGrid);
        p.Layout.Row = 1;
        g = uigridlayout(p, [1 9]);
        g.ColumnWidth = {150, 110, 120, 90, 150, 90, 100, '1x', 150};

        b1 = uibutton(g, 'Text', 'Load 4 Images', 'ButtonPushedFcn', @btnLoad4Images_Callback);
        b1.Layout.Column = 1;
        b2 = uibutton(g, 'Text', 'Process', 'ButtonPushedFcn', @btnProcess_Callback);
        b2.Layout.Column = 2;

        l1 = uilabel(g, 'Text', 'Pixel size (um)'); l1.Layout.Column = 3;
        app.ui.efPixelSize = uieditfield(g, 'numeric', 'Value', app.params.pixelSize_um);
        app.ui.efPixelSize.Layout.Column = 4;

        l2 = uilabel(g, 'Text', 'Confidence threshold'); l2.Layout.Column = 5;
        app.ui.efConfidence = uieditfield(g, 'numeric', 'Value', app.params.confidenceThreshold, ...
            'Limits', [0 1]);
        app.ui.efConfidence.Layout.Column = 6;

        b3 = uibutton(g, 'Text', 'Export', 'ButtonPushedFcn', @btnExport_Callback);
        b3.Layout.Column = 7;

        app.ui.lblStatus = uilabel(g, 'Text', 'Status: load 4 images to begin.');
        app.ui.lblStatus.Layout.Column = 8;

        b4 = uibutton(g, 'Text', 'About / Limitations', 'ButtonPushedFcn', @btnAbout_Callback);
        b4.Layout.Column = 9;
    end

    function buildNormalizedPanel(parentGrid)
        p = uipanel(parentGrid, 'Title', 'Normalized Images (Top / Bottom / Left / Right)');
        p.Layout.Column = 1;
        [app.ui.axNormTop, app.ui.axNormBottom, app.ui.axNormLeft, app.ui.axNormRight] = ...
            build2x2Axes(p, {'Top','Bottom','Left','Right'});
    end

    function [axTL, axTR, axBL, axBR] = build2x2Axes(parent, titles)
        g = uigridlayout(parent, [2 2]);
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

    function buildCombinedPanel(parentGrid)
        p = uipanel(parentGrid, 'Title', 'Combined Result (Phase Map) + Segmentation');
        p.Layout.Column = 2;
        g = uigridlayout(p, [3 1]);
        g.RowHeight = {22, '1x', 60};

        app.ui.lblMode = uilabel(g, 'Text', 'Mode: (no result yet)', 'FontWeight', 'bold');
        app.ui.lblMode.Layout.Row = 1;

        app.ui.axCombined = uiaxes(g);
        app.ui.axCombined.Layout.Row = 2;
        axis(app.ui.axCombined, 'image'); axis(app.ui.axCombined, 'off');
        app.ui.imgCombined = imagesc(app.ui.axCombined, zeros(2,2,3));

        sumGrid = uigridlayout(g, [2 4]);
        sumGrid.Layout.Row = 3;
        mk = @(txt) uilabel(sumGrid, 'Text', txt);
        mk('Glomeruli:'); app.ui.lblGlomCount = mk('-');
        mk('Tubules:');   app.ui.lblTubCount  = mk('-');
        mk('Mean phase (rad):'); app.ui.lblMeanPhase = mk('-');
        mk('Lumen ratio (mean):'); app.ui.lblLumenRatio = mk('-');
    end

    function buildDPCPanel(parentGrid)
        p = uipanel(parentGrid, 'Title', 'DPC Diagnostics');
        p.Layout.Column = 3;
        g = uigridlayout(p, [5 1]);
        g.RowHeight = {'1x', 24, '1x', 50, 22};

        imgRow = uigridlayout(g, [1 2]);
        imgRow.Layout.Row = 1;
        app.ui.axDPC_TB = uiaxes(imgRow); app.ui.axDPC_TB.Layout.Column = 1;
        app.ui.axDPC_LR = uiaxes(imgRow); app.ui.axDPC_LR.Layout.Column = 2;
        title(app.ui.axDPC_TB, 'Top-Bottom DPC'); title(app.ui.axDPC_LR, 'Left-Right DPC');
        for ax = [app.ui.axDPC_TB, app.ui.axDPC_LR]
            axis(ax, 'image'); axis(ax, 'off'); colormap(ax, gray);
        end
        app.ui.imgDPC_TB = imagesc(app.ui.axDPC_TB, zeros(2,2));
        app.ui.imgDPC_LR = imagesc(app.ui.axDPC_LR, zeros(2,2));

        histRow = uigridlayout(g, [1 2]);
        histRow.Layout.Row = 2;
        l = uilabel(histRow, 'Text', 'DPC histogram source:'); l.Layout.Column = 1;
        app.ui.ddHistSource = uidropdown(histRow, 'Items', {'Top-Bottom','Left-Right'}, ...
            'ValueChangedFcn', @(~,~) updateDPCHistogram());
        app.ui.ddHistSource.Layout.Column = 2;

        app.ui.axDPCHist = uiaxes(g);
        app.ui.axDPCHist.Layout.Row = 3;

        rangeGrid = uigridlayout(g, [2 1]);
        rangeGrid.Layout.Row = 4;
        app.ui.lblRangeTB = uilabel(rangeGrid, 'Text', 'DPC-TB range: -');
        app.ui.lblRangeLR = uilabel(rangeGrid, 'Text', 'DPC-LR range: -');

        app.ui.lblUncertain = uilabel(g, 'Text', 'Uncertain regions: -');
        app.ui.lblUncertain.Layout.Row = 5;
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
            % Create the status label BEFORE the button: the button callback
            % closure captures statusLbls(k) by value at creation time, so
            % the real label handle must exist first.
            statusLbls(k) = uilabel(g, 'Text', '(not loaded)');
            statusLbls(k).Layout.Row = k; statusLbls(k).Layout.Column = 3;
            b = uibutton(g, 'Text', 'Browse...', 'ButtonPushedFcn', @(src,ev) loadOneDirection(dirs{k}, statusLbls(k)));
            b.Layout.Row = k; b.Layout.Column = 2;
        end
        btnDone = uibutton(g, 'Text', 'Done', 'ButtonPushedFcn', @(~,~) close(dlg));
        btnDone.Layout.Row = 5; btnDone.Layout.Column = [1 3];
    end

    function loadOneDirection(which, statusLbl)
        [img, fname] = loadDirectionalImages(['Select ' which ' image']);
        if isempty(img); return; end
        app.data.raw.(which) = convertToProcessingFormat(img);
        if isvalid(statusLbl)
            statusLbl.Text = fname;
        end
        app.ui.lblStatus.Text = ['Loaded: ' which];
    end

% ===================================================================
%                       CALLBACKS - PROCESS
% ===================================================================
    function btnProcess_Callback(~, ~)
        raws = app.data.raw;
        [ok, msg] = validateDirectionalImages(raws);
        if ~ok
            uialert(app.ui.fig, msg, 'Cannot Process');
            return;
        end

        app.params.pixelSize_um = app.ui.efPixelSize.Value;
        app.params.confidenceThreshold = app.ui.efConfidence.Value;

        app.ui.lblStatus.Text = 'Registering...';
        [regImgs, shifts, warnMsg] = registerDirectionalImages(raws.top, raws.bottom, raws.left, raws.right, ...
            app.params.shiftWarnPx);
        app.data.registered = regImgs;
        if ~isempty(warnMsg)
            uialert(app.ui.fig, warnMsg, 'Registration Warning', 'Icon', 'warning');
        end

        app.ui.lblStatus.Text = 'Normalizing...';
        [normImgs, ~] = normalizeDirectionalImages(regImgs.top, regImgs.bottom, regImgs.left, regImgs.right);
        app.data.normalized = normImgs;
        updateNormalizedDisplay();

        app.ui.lblStatus.Text = 'Computing DPC images...';
        [dpcTB, dpcLR] = calculateDPCImages(normImgs.top, normImgs.bottom, normImgs.left, normImgs.right, app.params.epsilon);
        app.data.dpcTB = dpcTB; app.data.dpcLR = dpcLR;
        updateDPCDisplay();

        app.ui.lblStatus.Text = 'Reconstructing combined phase map...';
        [phase, mode] = reconstructDPCPhase(dpcTB, dpcLR, app.params);
        app.data.phase = phase; app.data.phaseMode = mode;

        app.ui.lblStatus.Text = 'Segmenting...';
        [tissueMask, glomLabels, tubuleLabels, lumenLabels, uncertainMask] = ...
            segmentKidneyStructures(phase, app.params);
        app.data.tissueMask = tissueMask; app.data.glomLabels = glomLabels;
        app.data.tubuleLabels = tubuleLabels; app.data.lumenLabels = lumenLabels;
        app.data.uncertainMask = uncertainMask;

        app.data.glomTable = calculateGlomerularFeatures(glomLabels, phase, tissueMask, app.params.pixelSize_um);
        app.data.tubTable  = calculateTubularFeatures(tubuleLabels, lumenLabels, phase, app.params.pixelSize_um);

        app.data.overlay = createSegmentationOverlay(phase, tissueMask, glomLabels, tubuleLabels, ...
            lumenLabels, uncertainMask);

        updateCombinedDisplay();
        app.ui.lblStatus.Text = 'Done.';
    end

% ===================================================================
%                        DISPLAY UPDATES
% ===================================================================
    function updateNormalizedDisplay()
        s = app.data.normalized;
        pairs = {app.ui.axNormTop,'top'; app.ui.axNormBottom,'bottom'; ...
                 app.ui.axNormLeft,'left'; app.ui.axNormRight,'right'};
        for i = 1:4
            ax = pairs{i,1}; d = pairs{i,2};
            img = s.(d);
            if isempty(img); continue; end
            imagesc(ax, mat2gray(img)); axis(ax,'image'); axis(ax,'off'); colormap(ax, gray);
        end
    end

    function updateDPCDisplay()
        app.ui.imgDPC_TB.CData = mat2gray(app.data.dpcTB);
        app.ui.imgDPC_LR.CData = mat2gray(app.data.dpcLR);
        axis(app.ui.axDPC_TB, 'image'); axis(app.ui.axDPC_LR, 'image');

        tb = app.data.dpcTB; lr = app.data.dpcLR;
        app.ui.lblRangeTB.Text = sprintf('DPC-TB range: [%.4f, %.4f]  std=%.4f', min(tb(:)), max(tb(:)), std(tb(:)));
        app.ui.lblRangeLR.Text = sprintf('DPC-LR range: [%.4f, %.4f]  std=%.4f', min(lr(:)), max(lr(:)), std(lr(:)));

        updateDPCHistogram();
    end

    function updateDPCHistogram()
        if isempty(app.data.dpcTB); return; end
        if strcmp(app.ui.ddHistSource.Value, 'Top-Bottom')
            data = app.data.dpcTB; lbl = 'DPC-TB';
        else
            data = app.data.dpcLR; lbl = 'DPC-LR';
        end
        cla(app.ui.axDPCHist);
        histogram(app.ui.axDPCHist, data(:), 60);
        title(app.ui.axDPCHist, [lbl ' histogram']);
    end

    function updateCombinedDisplay()
        app.ui.imgCombined.CData = app.data.overlay;
        axis(app.ui.axCombined, 'image');

        if strcmp(app.data.phaseMode, 'A')
            app.ui.lblMode.Text = 'Mode: A - CALIBRATED combined phase map';
            app.ui.lblMode.FontColor = [0 0.5 0];
        else
            app.ui.lblMode.Text = 'Mode: B - QUALITATIVE combined phase map (not calibrated)';
            app.ui.lblMode.FontColor = [0.7 0 0];
        end

        gT = app.data.glomTable; tT = app.data.tubTable;
        app.ui.lblGlomCount.Text = num2str(height(gT));
        app.ui.lblTubCount.Text = num2str(height(tT));
        app.ui.lblMeanPhase.Text = sprintf('%.4f', mean(app.data.phase(:)));
        if height(tT) > 0
            app.ui.lblLumenRatio.Text = sprintf('%.3f', mean(tT.LumenRatio, 'omitnan'));
        else
            app.ui.lblLumenRatio.Text = '-';
        end
        app.ui.lblUncertain.Text = sprintf('Uncertain regions: %d px (%.1f%% of tissue)', ...
            nnz(app.data.uncertainMask), 100*nnz(app.data.uncertainMask)/max(1,nnz(app.data.tissueMask)));
    end

% ===================================================================
%                          MISC CALLBACKS
% ===================================================================
    function btnAbout_Callback(~, ~)
        msg = [ ...
            "QPI-based kidney tissue structural segmentation and quantitative morphology analysis." newline ...
            "This is NOT a medical diagnostic system." newline newline ...
            "The combined phase map is a QUALITATIVE preview (Frankot-Chellappa gradient integration)" newline ...
            "unless calibrated transfer functions are supplied in code - see reconstructDPCPhase." newline newline ...
            "Segmentation is classical image processing (no trained model). Regions the algorithm" newline ...
            "cannot classify with reasonable confidence are labeled Uncertain (magenta), not guessed." ];
        uialert(app.ui.fig, strjoin(msg, ''), 'About / Limitations', 'Icon', 'info');
    end

    function btnExport_Callback(~, ~)
        if isempty(app.data.phase)
            uialert(app.ui.fig, 'Run "Process" first.', 'Nothing to Export');
            return;
        end
        outDir = uigetdir(pwd, 'Select export folder');
        if isequal(outDir, 0); return; end
        bundle.data = app.data;
        bundle.params = app.params;
        exportAnalysisResults(bundle, outDir);
        uialert(app.ui.fig, ['Export complete:' newline outDir], 'Export', 'Icon', 'success');
    end

end % ======================= END OF dpcQPIApp ============================


%% ========================================================================
%  DEFAULT PARAMETERS
%  ========================================================================
function params = defaultParams()
% DEFAULTPARAMS  Every tunable value in one place. GUI exposes only the
% two that matter most for casual use (pixel size, confidence threshold);
% everything else is a code-level [TUNE FIRST] default, changed here.
params.pixelSize_um = 1.0;      % [SET FIRST] effective sample-plane pixel size, micrometers
params.regParam      = 1e-2;    % [TUNE FIRST] Tikhonov/Fourier-integration regularization
params.epsilon        = 1e-3;   % [TUNE FIRST] DPC ratio denominator epsilon; scale to your
                                 % images' intensity range (see calculateDPCImages)
params.shiftWarnPx   = 50;      % warn if a registration shift exceeds this many pixels
params.confidenceThreshold = 0.4; % [TUNE FIRST] glomerulus/tubule candidates below this
                                   % confidence score are relabeled "Uncertain"
params.Hu = []; params.Hv = []; % calibrated transfer functions (Mode A); empty => Mode B

% ---- Segmentation internals (code-level tuning; see segmentKidneyStructures) ----
params.minTissueAreaPx = 500;
params.glomTextureWindow = 9;
params.glomIntensityPercentile = 80;
params.glomTexturePercentile = 70;
params.glomCloseRadius = 3;
params.glomAreaMinPx = 300; params.glomAreaMaxPx = 20000;
% NOTE: circularity is NOT a hard cutoff here - area range is the hard gate,
% and circularity instead feeds the confidence score (see detectGlomeruli),
% so an oddly-shaped-but-right-sized candidate becomes "Uncertain" rather
% than being silently discarded or silently accepted.
params.glomWatershedSuppression = 2;
params.glomRingWidthPx = 15;
params.tubuleCloseRadius = 2;
params.tubuleAreaMinPx = 150; params.tubuleAreaMaxPx = 15000;
params.tubuleWatershedSuppression = 2;
params.lumenIntensityPercentile = 30;
params.lumenGrowToleranceFactor = 1.3;
params.lumenOpenRadius = 1;
params.lumenMinAreaFraction = 0.02;
end


%% ========================================================================
%  IMAGE INPUT
%  ========================================================================
function [img, fname] = loadDirectionalImages(promptTitle)
% LOADDIRECTIONALIMAGES  Prompts for one image file (png/tif/jpg/bmp/mat).
img = []; fname = '';
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
fname = [nm ext];
end


function gray = convertToProcessingFormat(img)
% CONVERTTOPROCESSINGFORMAT  RGB or any numeric class -> double grayscale,
% for all downstream registration/normalization/DPC calculations.
if size(img, 3) == 3
    gray = double(rgb2gray(img));
else
    gray = double(img(:,:,1));
end
end


function [ok, msg] = validateDirectionalImages(raws)
% VALIDATEDIRECTIONALIMAGES  All four present and identical size - DPC
% math is pixel-wise and silently wrong if this doesn't hold.
ok = true; msg = '';
dirs = {'top','bottom','left','right'};
missing = {};
for i = 1:4
    if isempty(raws.(dirs{i})); missing{end+1} = dirs{i}; end %#ok<AGROW>
end
if ~isempty(missing)
    ok = false; msg = ['Missing image(s): ' strjoin(missing, ', ')]; return;
end
sz = size(raws.top);
for i = 2:4
    if ~isequal(size(raws.(dirs{i})), sz)
        ok = false;
        msg = sprintf('%s image size %s does not match Top image size %s.', ...
            dirs{i}, mat2str(size(raws.(dirs{i}))), mat2str(sz));
        return;
    end
end
end


%% ========================================================================
%  REGISTRATION
%  ========================================================================
function [regImgs, shifts, warnMsg] = registerDirectionalImages(top, bottom, left, right, shiftWarnPx)
% REGISTERDIRECTIONALIMAGES  Translation-only phase-correlation registration
% (imregcorr) of Bottom/Left/Right onto Top. Runs automatically/silently;
% only a large-shift warning is surfaced to the user.
warnMsg = '';
regImgs = struct('top', top, 'bottom', [], 'left', [], 'right', []);
shifts = struct('bottom', [0 0], 'left', [0 0], 'right', [0 0]);
refView = imref2d(size(top));
dirs = {'bottom','left','right'};
movs = {bottom, left, right};
warnParts = {};

for i = 1:3
    d = dirs{i};
    try
        tform = imregcorr(movs{i}, top, 'translation');
        [dx, dy] = tformTranslation(tform);
        regImgs.(d) = imwarp(movs{i}, tform, 'OutputView', refView);
    catch ME
        warnParts{end+1} = sprintf('Registration failed for %s (%s) - using unregistered image.', d, ME.message); %#ok<AGROW>
        dx = 0; dy = 0;
        regImgs.(d) = movs{i};
    end
    shifts.(d) = [dx, dy];
    if abs(dx) > shiftWarnPx || abs(dy) > shiftWarnPx
        warnParts{end+1} = sprintf('%s registration shift is large: dx=%.1f, dy=%.1f px.', d, dx, dy); %#ok<AGROW>
    end
end
if ~isempty(warnParts)
    warnMsg = strjoin(warnParts, newline);
end
end


function [dx, dy] = tformTranslation(tform)
% TFORMTRANSLATION  Works across MATLAB releases: newer imregcorr returns
% an object with a .Translation property; older releases return affine2d
% with a .T matrix.
if isprop(tform, 'Translation')
    t = tform.Translation; dx = t(1); dy = t(2);
elseif isprop(tform, 'T')
    dx = tform.T(3,1); dy = tform.T(3,2);
else
    A = tform.A; dx = A(1,3); dy = A(2,3);
end
end


%% ========================================================================
%  NORMALIZATION
%  ========================================================================
function [normImgs, normFactors] = normalizeDirectionalImages(top, bottom, left, right)
% NORMALIZEDIRECTIONALIMAGES  Scales each registered image SEPARATELY so
% its mean intensity matches the average mean across all four - corrects
% illumination-direction brightness differences without ever averaging
% the four images together (each stays a distinct array).
dirs = {'top','bottom','left','right'};
imgs = {top, bottom, left, right};
means = cellfun(@(im) mean(im(:)), imgs);
target = mean(means);

normImgs = struct(); normFactors = struct();
for i = 1:4
    factor = target / (means(i) + eps);
    normImgs.(dirs{i}) = imgs{i} * factor;
    normFactors.(dirs{i}) = struct('meanBefore', means(i), 'meanAfter', target, 'factor', factor);
end
end


%% ========================================================================
%  DPC IMAGE CALCULATION
%  ========================================================================
function [dpcTB, dpcLR] = calculateDPCImages(topNorm, bottomNorm, leftNorm, rightNorm, epsilon)
% CALCULATEDPCIMAGES  DPC_TB=(Top-Bottom)/(Top+Bottom+eps); DPC_LR likewise
% for Left/Right. Intensity-asymmetry maps - not yet phase.
dpcTB = (topNorm - bottomNorm) ./ (topNorm + bottomNorm + epsilon);
dpcLR = (leftNorm - rightNorm) ./ (leftNorm + rightNorm + epsilon);
end


%% ========================================================================
%  PHASE RECONSTRUCTION (combined result)
%  ========================================================================
function [phase, mode] = reconstructDPCPhase(dpcTB, dpcLR, params)
% RECONSTRUCTDPCPHASE  Mode A (calibrated) activates only if params.Hu/Hv
% (precomputed DPC phase transfer functions matching image size) are set
% in code - this file does not synthesize them from NA/wavelength, since
% an incorrect physical model would silently produce a wrong phase map.
% Otherwise Mode B: Frankot-Chellappa Fourier gradient integration of
% dpcTB/dpcLR treated as vertical/horizontal gradient-like signals -
% standard, well-defined math, but a QUALITATIVE PREVIEW, not a
% calibrated quantitative phase map.
hasTF = isfield(params, 'Hu') && isfield(params, 'Hv') && ~isempty(params.Hu) && ~isempty(params.Hv) ...
    && isequal(size(params.Hu), size(dpcTB)) && isequal(size(params.Hv), size(dpcLR));

if hasTF
    mode = 'A';
    Fu = fft2(dpcTB); Fv = fft2(dpcLR);
    Hu = params.Hu; Hv = params.Hv;
    numerator = conj(Hu) .* Fu + conj(Hv) .* Fv;
    denominator = abs(Hu).^2 + abs(Hv).^2 + params.regParam;
    phase = real(ifft2(numerator ./ denominator));
else
    mode = 'B';
    phase = integratePhaseGradientQualitatively(dpcTB, dpcLR, params.regParam);
end
end


function surfaceOut = integratePhaseGradientQualitatively(gx, gy, regParam)
% INTEGRATEPHASEGRADIENTQUALITATIVELY  Frankot-Chellappa Fourier gradient
% integration - standard technique, but gx/gy here are DPC contrast
% ratios, not verified physical gradients, so the result is a QUALITATIVE
% PREVIEW only.
[ny, nx] = size(gx);
[u, v] = meshgrid((0:nx-1) - floor(nx/2), (0:ny-1) - floor(ny/2));
u = ifftshift(u) * 2 * pi / nx;
v = ifftshift(v) * 2 * pi / ny;
Fx = fft2(gx); Fy = fft2(gy);
denom = (u.^2 + v.^2 + regParam);
Z = (-1i * u .* Fx - 1i * v .* Fy) ./ denom;
Z(1,1) = 0;
surfaceOut = real(ifft2(Z));
end


%% ========================================================================
%  SEGMENTATION  (classical image processing, no training data)
%  ========================================================================
function [tissueMask, glomLabels, tubuleLabels, lumenLabels, uncertainMask] = ...
    segmentKidneyStructures(phase, params)
% SEGMENTKIDNEYSTRUCTURES  Wraps tissue/glomerulus/tubule/lumen detection
% and applies a confidence score to every glomerulus/tubule candidate;
% low-confidence candidates are pulled OUT of glomLabels/tubuleLabels and
% into uncertainMask instead of being guessed as a specific structure.
% Confidence = 0.5*circularity fit + 0.5*area fit to the expected range
% (see detectGlomeruli/detectTubules) - a simple, inspectable heuristic,
% not a statistically calibrated probability.

img = mat2gray(phase); % for thresholding/texture only - measurements use raw phase
tissueMask = segmentTissueRegion(img, params);

[glomLabels, glomConf] = detectGlomeruli(img, tissueMask, params);
[tubuleLabels, tubConf] = detectTubules(img, tissueMask, glomLabels, params);

[glomLabels, uncertainGlom] = splitByConfidence(glomLabels, glomConf, params.confidenceThreshold);
[tubuleLabels, uncertainTub] = splitByConfidence(tubuleLabels, tubConf, params.confidenceThreshold);
uncertainMask = uncertainGlom | uncertainTub;

lumenLabels = detectLumens(img, tubuleLabels, params);
end


function mask = segmentTissueRegion(img, params)
% SEGMENTTISSUEREGION  Otsu threshold + morphological cleanup to separate
% kidney tissue from empty background.
level = graythresh(img);
mask = imbinarize(img, level);
mask = imopen(mask, strel('disk', 2));
mask = imfill(mask, 'holes');
mask = bwareaopen(mask, params.minTissueAreaPx);
end


function [keptLabels, uncertainMask] = splitByConfidence(labels, conf, thresh)
% SPLITBYCONFIDENCE  Moves any labeled region whose confidence score is
% below thresh out of the label matrix and into a logical uncertain mask.
keptLabels = labels;
uncertainMask = false(size(labels));
n = max(labels(:));
for i = 1:n
    m = labels == i;
    if ~any(m(:)); continue; end
    if ~isKey_(conf, i) || conf(i) < thresh
        keptLabels(m) = 0;
        uncertainMask(m) = true;
    end
end
keptLabels = bwlabel(keptLabels > 0);
end


function tf = isKey_(conf, i)
% ISKEY_  conf is a plain numeric vector indexed by label id (1..n); this
% just guards against an out-of-range index.
tf = i >= 1 && i <= numel(conf);
end


function [glomLabels, confidence] = detectGlomeruli(img, tissueMask, params)
% DETECTGLOMERULI  Candidates = tissue regions with both high phase/
% intensity and high local texture (dense glomerular tuft cellularity),
% consolidated, watershed-split where touching, then filtered by area and
% circularity. confidence(i) in [0,1] combines circularity fit and area
% fit to the expected range - low values get relabeled Uncertain by the
% caller, not guessed as glomerulus.
texture = mat2gray(stdfilt(img, true(params.glomTextureWindow)));

tissueVals = img(tissueMask); textureVals = texture(tissueMask);
glomLabels = zeros(size(img)); confidence = [];
if isempty(tissueVals); return; end

intThresh = prctile(tissueVals, params.glomIntensityPercentile);
texThresh = prctile(textureVals, params.glomTexturePercentile);
candidate = tissueMask & (img >= intThresh) & (texture >= texThresh);
candidate = imclose(candidate, strel('disk', params.glomCloseRadius));
candidate = imfill(candidate, 'holes');
candidate = bwareaopen(candidate, params.glomAreaMinPx);
if ~any(candidate(:)); return; end

D = -bwdist(~candidate);
markerMask = imextendedmin(D, params.glomWatershedSuppression);
Lws = watershed(imimposemin(D, markerMask));
candidate(Lws == 0) = 0;

CC = bwconncomp(candidate);
stats = regionprops(CC, 'Area', 'Perimeter');
keepIdx = []; conf = [];
idealArea = mean([params.glomAreaMinPx, params.glomAreaMaxPx]);
for i = 1:CC.NumObjects
    area = stats(i).Area;
    circVal = 4 * pi * area / (stats(i).Perimeter^2 + eps);
    if area >= params.glomAreaMinPx && area <= params.glomAreaMaxPx
        keepIdx(end+1) = i; %#ok<AGROW>
        circFit = min(circVal, 1);
        areaFit = max(0, 1 - abs(area - idealArea) / idealArea);
        conf(end+1) = 0.5 * circFit + 0.5 * areaFit; %#ok<AGROW>
    end
end
if isempty(keepIdx); return; end

L = labelmatrix(CC);
glomLabels = zeros(size(img));
confidence = zeros(1, numel(keepIdx));
for k = 1:numel(keepIdx)
    glomLabels(L == keepIdx(k)) = k;
    confidence(k) = conf(k);
end
end


function [tubuleLabels, confidence] = detectTubules(img, tissueMask, glomLabels, params)
% DETECTTUBULES  Candidates = compact roughly-round tissue components that
% are not part of a glomerulus, watershed-split, filtered by area and
% circularity. confidence as in detectGlomeruli.
nonGlom = tissueMask & (glomLabels == 0);
tubuleLabels = zeros(size(img)); confidence = [];
if ~any(nonGlom(:)); return; end

level = graythresh(img(nonGlom));
candidate = nonGlom & imbinarize(img, level);
candidate = imclose(candidate, strel('disk', params.tubuleCloseRadius));
candidate = imfill(candidate, 'holes');
candidate = bwareaopen(candidate, params.tubuleAreaMinPx);
if ~any(candidate(:)); return; end

D = -bwdist(~candidate);
markerMask = imextendedmin(D, params.tubuleWatershedSuppression);
Lws = watershed(imimposemin(D, markerMask));
candidate(Lws == 0) = 0;

CC = bwconncomp(candidate);
stats = regionprops(CC, 'Area', 'Perimeter');
keepIdx = []; conf = [];
idealArea = mean([params.tubuleAreaMinPx, params.tubuleAreaMaxPx]);
for i = 1:CC.NumObjects
    area = stats(i).Area;
    circVal = 4 * pi * area / (stats(i).Perimeter^2 + eps);
    if area >= params.tubuleAreaMinPx && area <= params.tubuleAreaMaxPx
        keepIdx(end+1) = i; %#ok<AGROW>
        circFit = min(circVal, 1);
        areaFit = max(0, 1 - abs(area - idealArea) / idealArea);
        conf(end+1) = 0.5 * circFit + 0.5 * areaFit; %#ok<AGROW>
    end
end
if isempty(keepIdx); return; end

L = labelmatrix(CC);
tubuleLabels = zeros(size(img));
confidence = zeros(1, numel(keepIdx));
for k = 1:numel(keepIdx)
    tubuleLabels(L == keepIdx(k)) = k;
    confidence(k) = conf(k);
end
end


function lumenLabels = detectLumens(img, tubuleLabels, params)
% DETECTLUMENS  Region growing (morphological reconstruction) from a
% conservative low-phase seed within each tubule, out to a looser
% low-phase limit - more robust than a single hard threshold. lumenLabels
% shares tubuleLabels' numeric IDs (no separate renumbering).
lumenLabels = zeros(size(img));
numTub = max(tubuleLabels(:));
for t = 1:numTub
    tubMask = tubuleLabels == t;
    if ~any(tubMask(:)); continue; end
    pix = img(tubMask);
    seedThresh = prctile(pix, params.lumenIntensityPercentile);
    growThresh = seedThresh * params.lumenGrowToleranceFactor;
    seed = tubMask & (img <= seedThresh);
    growLimit = tubMask & (img <= growThresh);
    grown = imreconstruct(seed, growLimit);
    grown = imopen(grown, strel('disk', params.lumenOpenRadius));
    grown = bwareaopen(grown, max(1, round(params.lumenMinAreaFraction * nnz(tubMask))));
    outerRim = tubMask & ~imerode(tubMask, strel('disk', 1));
    grown = grown & ~imdilate(outerRim, strel('disk', 1));
    lumenLabels(grown) = t;
end
end


%% ========================================================================
%  QUANTITATIVE ANALYSIS
%  ========================================================================
function glomTable = calculateGlomerularFeatures(glomLabels, phase, tissueMask, pixelSize_um)
% CALCULATEGLOMERULARFEATURES  Area, EquivDiameter, Circularity
% (4*pi*Area/Perimeter^2), MeanPhase, MaxPhase, StdPhase, and phase
% difference vs. a ring of surrounding tissue, per detected glomerulus.
n = max(glomLabels(:));
ID=[]; Area_um2=[]; EquivDiam_um=[]; Circularity=[]; MeanPhase=[]; MaxPhase=[]; StdPhase=[]; PhaseDiffSurrounding=[];
for i = 1:n
    m = glomLabels == i;
    if ~any(m(:)); continue; end
    s = regionprops(m, 'Area', 'Perimeter', 'EquivDiameter');
    area = s(1).Area;
    circVal = 4 * pi * area / (s(1).Perimeter^2 + eps);
    ring = imdilate(m, strel('disk', 15)) & ~m & tissueMask;
    glomVals = phase(m); ringVals = phase(ring);
    ID(end+1,1) = i; %#ok<AGROW>
    Area_um2(end+1,1) = area * pixelSize_um^2; %#ok<AGROW>
    EquivDiam_um(end+1,1) = s(1).EquivDiameter * pixelSize_um; %#ok<AGROW>
    Circularity(end+1,1) = circVal; %#ok<AGROW>
    MeanPhase(end+1,1) = mean(glomVals); %#ok<AGROW>
    MaxPhase(end+1,1) = max(glomVals); %#ok<AGROW>
    StdPhase(end+1,1) = std(glomVals); %#ok<AGROW>
    if isempty(ringVals)
        PhaseDiffSurrounding(end+1,1) = NaN; %#ok<AGROW>
    else
        PhaseDiffSurrounding(end+1,1) = mean(glomVals) - mean(ringVals); %#ok<AGROW>
    end
end
glomTable = table(ID, Area_um2, EquivDiam_um, Circularity, MeanPhase, MaxPhase, StdPhase, PhaseDiffSurrounding);
end


function tubTable = calculateTubularFeatures(tubuleLabels, lumenLabels, phase, pixelSize_um)
% CALCULATETUBULARFEATURES  TubuleArea, LumenArea, LumenRatio (=Lumen/
% Tubule area), estimated WallThickness (from equivalent diameters -
% an average-radial APPROXIMATION, not a per-point measurement),
% Circularity, MeanWallPhase, MeanLumenPhase, WallLumenPhaseDiff.
n = max(tubuleLabels(:));
ID=[]; TubuleArea_um2=[]; LumenArea_um2=[]; LumenRatio=[]; WallThickness_um=[];
Circularity=[]; MeanWallPhase=[]; MeanLumenPhase=[]; WallLumenPhaseDiff=[];
for t = 1:n
    tubMask = tubuleLabels == t;
    if ~any(tubMask(:)); continue; end
    lumMask = lumenLabels == t;
    wallMask = tubMask & ~lumMask;
    if ~any(wallMask(:)); continue; end
    sT = regionprops(tubMask, 'Area', 'Perimeter', 'EquivDiameter');
    tArea = sT(1).Area;
    circVal = 4 * pi * tArea / (sT(1).Perimeter^2 + eps);
    lArea = nnz(lumMask);
    if lArea > 0
        sL = regionprops(lumMask, 'EquivDiameter');
        wallThick = max((sT(1).EquivDiameter - sL(1).EquivDiameter) / 2, 0) * pixelSize_um;
        meanLumenPhase = mean(phase(lumMask));
    else
        wallThick = NaN; meanLumenPhase = NaN;
    end
    meanWallPhase = mean(phase(wallMask));
    ID(end+1,1) = t; %#ok<AGROW>
    TubuleArea_um2(end+1,1) = tArea * pixelSize_um^2; %#ok<AGROW>
    LumenArea_um2(end+1,1) = lArea * pixelSize_um^2; %#ok<AGROW>
    LumenRatio(end+1,1) = lArea / tArea; %#ok<AGROW>
    WallThickness_um(end+1,1) = wallThick; %#ok<AGROW>
    Circularity(end+1,1) = circVal; %#ok<AGROW>
    MeanWallPhase(end+1,1) = meanWallPhase; %#ok<AGROW>
    MeanLumenPhase(end+1,1) = meanLumenPhase; %#ok<AGROW>
    WallLumenPhaseDiff(end+1,1) = meanWallPhase - meanLumenPhase; %#ok<AGROW>
end
tubTable = table(ID, TubuleArea_um2, LumenArea_um2, LumenRatio, WallThickness_um, ...
    Circularity, MeanWallPhase, MeanLumenPhase, WallLumenPhaseDiff);
end


%% ========================================================================
%  OVERLAY  (glomerulus=red, tubule=green, lumen=blue, uncertain=magenta,
%  background=transparent)
%  ========================================================================
function overlay = createSegmentationOverlay(phase, tissueMask, glomLabels, tubuleLabels, lumenLabels, uncertainMask) %#ok<INUSD>
base = mat2gray(phase);
overlay = repmat(base, 1, 1, 3);
alpha = 0.45;

glomMask = glomLabels > 0;
lumMask  = lumenLabels > 0;
tubMask  = (tubuleLabels > 0) & ~glomMask & ~lumMask;
uncMask  = uncertainMask & ~glomMask & ~tubMask & ~lumMask;

overlay = blendColor(overlay, glomMask, [1 0 0], alpha);
overlay = blendColor(overlay, tubMask,  [0 1 0], alpha);
overlay = blendColor(overlay, lumMask,  [0 0 1], alpha);
overlay = blendColor(overlay, uncMask,  [1 0 1], alpha);
end


function ov = blendColor(ov, mask, color, alpha)
for c = 1:3
    ch = ov(:,:,c);
    ch(mask) = (1 - alpha) * ch(mask) + alpha * color(c);
    ov(:,:,c) = ch;
end
end


%% ========================================================================
%  EXPORT
%  ========================================================================
function exportAnalysisResults(bundle, outDir)
% EXPORTANALYSISRESULTS  Saves normalized images, DPC-TB/LR, the combined
% phase map (MAT+TIFF), the segmentation overlay, measurement tables
% (CSV), parameters, and a combined project MAT file into outDir.
if ~exist(outDir, 'dir'); mkdir(outDir); end
d = bundle.data;

dirs = {'top','bottom','left','right'};
for i = 1:4
    dname = dirs{i};
    if ~isempty(d.normalized.(dname))
        imwrite(mat2gray(d.normalized.(dname)), fullfile(outDir, ['normalized_' dname '.tiff']));
    end
end

if ~isempty(d.dpcTB)
    imwrite(mat2gray(d.dpcTB), fullfile(outDir, 'DPC_TB.png'));
    imwrite(mat2gray(d.dpcLR), fullfile(outDir, 'DPC_LR.png'));
end

if ~isempty(d.phase)
    phase = d.phase; %#ok<NASGU>
    save(fullfile(outDir, 'combined_phase_map.mat'), 'phase');
    imwrite(mat2gray(d.phase), fullfile(outDir, 'combined_phase_map.tiff'));
end
if ~isempty(d.overlay)
    imwrite(d.overlay, fullfile(outDir, 'segmentation_overlay.png'));
end

if ~isempty(d.glomTable); writetable(d.glomTable, fullfile(outDir, 'glomeruli.csv')); end
if ~isempty(d.tubTable);  writetable(d.tubTable,  fullfile(outDir, 'tubules.csv'));  end

params = bundle.params; %#ok<NASGU>
save(fullfile(outDir, 'processing_parameters.mat'), 'params');
save(fullfile(outDir, 'project.mat'), 'bundle');
end
