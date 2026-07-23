function kidneyQPIAnalysis()
%KIDNEYQPIANALYSIS  Structural segmentation & quantitative morphology
%analysis of mouse kidney QPI (Quantitative Phase Imaging) images.
%
% Segments: 1) Glomerulus  2) Renal tubule  3) Tubular lumen  4) Background
%
% ------------------------------------------------------------------
% IMPORTANT / LIMITATION
% ------------------------------------------------------------------
% This program performs STRUCTURAL SEGMENTATION and QUANTITATIVE
% MORPHOLOGY ANALYSIS ONLY (area, shape, phase statistics). It is a
% classical image-processing prototype - it uses NO trained deep-
% learning model and NO labeled ground truth. It DOES NOT diagnose
% kidney disease and must not be presented, used, or marketed as a
% diagnostic tool. All outputs require review by a qualified
% researcher/pathologist. Automatic detection of glomeruli/tubules
% from unlabeled classical image processing is inherently imperfect
% (see TROUBLESHOOTING below) - a manual/semi-automatic correction
% tool is provided for this reason (see Section 6 / manualCorrectionUI).
%
% ------------------------------------------------------------------
% HOW TO RUN
% ------------------------------------------------------------------
% 1. Open this file in the MATLAB Editor and press "Run" (F5), or type
%       kidneyQPIAnalysis
%    at the MATLAB command line.
% 2. Choose "Single Image" (interactive analysis with dashboard, ROI
%    tool, and manual correction) or "Folder (Batch)" (automatic
%    analysis of every image in a folder, results saved to disk).
% 3. Select the image type (Phase Map vs Intensity image) and pixel
%    size (micrometers/pixel) when prompted. If you don't know the
%    pixel size, enter 1 and all "_um" results will simply be in pixel
%    units instead of micrometers.
% 4. Supported formats: .png .tif/.tiff .jpg/.jpeg .mat
%    For .mat files you will be asked to pick which numeric variable
%    holds the phase map (if more than one candidate variable exists).
% 5. In interactive mode, review the automatic segmentation. If it
%    looks wrong, choose "Manual Correction" to add/remove glomeruli
%    or tubules by hand before the measurement tables are finalized.
% 6. Use the "ROI Analysis" button any time to draw/click a region and
%    inspect its phase statistics, histogram, and line profiles.
% 7. Use "Export Results" to save the overlay image, masks (.mat),
%    and measurement tables (.csv / .xlsx) to a folder you choose.
%
% ------------------------------------------------------------------
% REQUIRED MATLAB TOOLBOXES
% ------------------------------------------------------------------
%   - MATLAB (base)                     : uifigure/figure/uicontrol/uitable, tables, file I/O
%   - Image Processing Toolbox (REQUIRED): imread, imbinarize, graythresh, adapthisteq,
%                                          strel/imopen/imclose/imfill/bwareaopen, bwdist,
%                                          imextendedmin/imimposemin/watershed, activecontour,
%                                          imreconstruct, regionprops, drawfreehand/drawpolygon,
%                                          visboundaries, label2rgb
%   - Statistics and Machine Learning Toolbox (OPTIONAL): only if you extend the stats used;
%                                          all statistics in this script (mean/median/std/
%                                          prctile) work with base MATLAB + Image Processing Toolbox.
%
% ------------------------------------------------------------------
% TROUBLESHOOTING - "No glomeruli / no tubules detected"
% ------------------------------------------------------------------
%   1. Check tissue segmentation first (subplot "Segmentation mask"). If
%      the whole image is background, adjust params.tissueThresholdMethod/
%      params.tissueManualThreshold, or set params.invertTissueMask = true
%      if your background phase is HIGHER than tissue phase.
%   2. If tissue is detected but no glomeruli: lower
%      params.glomIntensityPercentile and/or params.glomTexturePercentile
%      (these define how "bright"/"textured" a region must be to be a
%      glomerulus candidate), and/or lower params.glomAreaMinPx if your
%      glomeruli are smaller than expected at your magnification/pixel size.
%   3. If glomeruli merge into one blob or are missing due to over-
%      splitting: adjust params.glomWatershedSuppression (higher = fewer,
%      larger regions; lower = more aggressive splitting).
%   4. If tubules are missed: lower params.tubuleAreaMinPx /
%      params.tubuleCircularityMin (tubule cross-sections are often less
%      circular than glomeruli, especially if cut obliquely).
%   5. If lumens are missed: raise params.lumenIntensityPercentile (defines
%      what fraction of low-phase pixels inside a tubule counts as lumen).
%   6. Always re-check params.pixelSize - area/diameter filters are defined
%      in PIXELS (Px suffix) in getDefaultParams(); if your image
%      resolution differs a lot from what these defaults assume, most
%      area-based filters will reject everything.
%   7. If nothing works reliably for your dataset: use "Manual Correction"
%      to draw glomeruli/tubules by hand - all downstream measurements
%      (Section 5) work identically on manually drawn regions.
%
% All tunable parameters live in getDefaultParams() below and are
% flagged with "[TUNE FIRST]" where they most directly affect detection.

close all; clc;

%% ============================ 1. PARAMETERS ============================
% Edit getDefaultParams() below to change default behavior.
params = getDefaultParams();

%% ============================ MODE SELECTION ============================
mode = questdlg(['Load a single image (interactive analysis) or a folder ' ...
    '(automatic batch analysis)?'], 'Kidney QPI Analysis', ...
    'Single Image','Folder (Batch)','Single Image');
if isempty(mode)
    return;
end

imageList = loadKidneyImage(mode);
if isempty(imageList)
    warndlg('No image loaded. Exiting.','Kidney QPI Analysis');
    return;
end

if strcmp(mode,'Folder (Batch)')
    outDir = uigetdir(pwd,'Select output folder for batch results');
    if isequal(outDir,0)
        outDir = fullfile(pwd,'KidneyQPI_BatchOutput');
    end
    if ~exist(outDir,'dir'); mkdir(outDir); end

    allGlomT = table();
    allTubT  = table();
    for k = 1:numel(imageList)
        fprintf('Processing %d/%d: %s\n', k, numel(imageList), imageList(k).name);
        result = analyzeOneImage(imageList(k), params, false);

        gT = result.glomTable; gT.ImageName = repmat({imageList(k).name}, height(gT), 1);
        tT = result.tubTable;  tT.ImageName = repmat({imageList(k).name}, height(tT), 1);
        allGlomT = [allGlomT; gT]; %#ok<AGROW>
        allTubT  = [allTubT;  tT]; %#ok<AGROW>

        exportResults(outDir, imageList(k).name, result);
    end
    if ~isempty(allGlomT); writetable(allGlomT, fullfile(outDir,'ALL_glomeruli.csv')); end
    if ~isempty(allTubT);  writetable(allTubT,  fullfile(outDir,'ALL_tubules.csv'));  end
    msgbox(sprintf('Batch complete.\nResults saved to:\n%s', outDir), 'Kidney QPI Analysis');
else
    analyzeOneImage(imageList(1), params, true);
end

end % ======================= END OF MAIN FUNCTION =========================


%% ========================================================================
%  1. IMAGE LOADING
%  ========================================================================
function imageList = loadKidneyImage(mode)
% LOADKIDNEYIMAGE  Lets the user pick one file or a whole folder of QPI
% images (png/tif/tiff/jpg/mat). For .mat files, prompts the user to
% choose which numeric variable holds the phase/intensity map.
%
% WHY: QPI acquisition software commonly exports either a raw phase-map
% image (png/tif) or a MATLAB workspace .mat file containing the
% reconstructed phase matrix, sometimes alongside other variables
% (amplitude, metadata) - hence the variable-selection step for .mat.

imageList = struct('name',{},'rawImage',{},'pixelSize',{},'isPhaseMap',{});

isPhaseAns = questdlg(['Are these images quantitative PHASE maps ' ...
    '(e.g. radians or nm optical path length) or grayscale INTENSITY images?'], ...
    'Image Type','Phase Map','Intensity Image','Phase Map');
if isempty(isPhaseAns); isPhaseAns = 'Phase Map'; end
isPhaseMap = strcmp(isPhaseAns,'Phase Map');

pxAns = inputdlg({'Pixel size (micrometers per pixel). Enter 1 if unknown:'}, ...
    'Pixel Size', 1, {'1'});
if isempty(pxAns)
    pixelSize = 1;
else
    pixelSize = str2double(pxAns{1});
end
if isnan(pixelSize) || pixelSize <= 0
    pixelSize = 1;
end

if strcmp(mode,'Single Image')
    [f,p] = uigetfile({'*.png;*.tif;*.tiff;*.jpg;*.jpeg;*.mat', ...
        'Supported Files (*.png,*.tif,*.tiff,*.jpg,*.jpeg,*.mat)'}, 'Select QPI image');
    if isequal(f,0); return; end
    files = {fullfile(p,f)};
else
    d = uigetdir(pwd,'Select folder containing QPI images');
    if isequal(d,0); return; end
    exts = {'*.png','*.tif','*.tiff','*.jpg','*.jpeg','*.mat'};
    files = {};
    for e = 1:numel(exts)
        L = dir(fullfile(d,exts{e}));
        for i = 1:numel(L)
            files{end+1} = fullfile(d,L(i).name); %#ok<AGROW>
        end
    end
    if isempty(files)
        warndlg('No supported image files found in that folder.','Kidney QPI Analysis');
        return;
    end
end

for i = 1:numel(files)
    fp = files{i};
    [~, nm, ext] = fileparts(fp);
    try
        if strcmpi(ext, '.mat')
            S = load(fp);
            vn = fieldnames(S);
            isCandidate = structfun(@(v) isnumeric(v) && ismatrix(v) && numel(v) > 100, S);
            numericVars = vn(isCandidate);
            if isempty(numericVars)
                warning('No suitable numeric matrix variable found in %s. Skipping.', fp);
                continue;
            elseif numel(numericVars) == 1
                sel = numericVars{1};
            else
                [idx, ok] = listdlg('ListString', numericVars, 'SelectionMode', 'single', ...
                    'PromptString', sprintf('Select phase-map variable in %s:', [nm ext]));
                if ~ok; continue; end
                sel = numericVars{idx};
            end
            img = double(S.(sel));
        else
            img = imread(fp);
            if size(img,3) == 3
                img = rgb2gray(img);
            end
            img = double(img);
        end
    catch ME
        warning('Failed to load %s: %s', fp, ME.message);
        continue;
    end

    imageList(end+1) = struct('name', [nm ext], 'rawImage', img, ...
        'pixelSize', pixelSize, 'isPhaseMap', isPhaseMap); %#ok<AGROW>
end
end


%% ========================================================================
%  DEFAULT PARAMETERS  -  EDIT THESE FIRST WHEN TUNING TO A NEW DATASET
%  ========================================================================
function params = getDefaultParams()
% GETDEFAULTPARAMS  Central place for every tunable threshold/size used
% by the pipeline. Nothing downstream hard-codes a magic number - if
% detection is wrong for your dataset, change values here (or edit the
% struct returned by this function) rather than editing the algorithms.

params = struct();

% ---- Pixel size (overwritten by the value you enter in loadKidneyImage) ----
params.pixelSize = 1;              % micrometers/pixel; 1 = report in pixel units

% ---- 2. Preprocessing ----------------------------------------------------
params.backgroundMorphRadius = 40; % [TUNE FIRST] disk radius (px) used to estimate
                                    % uneven illumination/phase background via
                                    % morphological opening. Too small -> real
                                    % structures get subtracted as "background".
                                    % Too large -> shading not fully removed.
params.invertTissueMask = false;   % set true if your background phase/intensity is
                                    % HIGHER than tissue (rare, but depends on setup)
params.denoiseMethod = 'gaussian'; % 'gaussian' | 'median' | 'none'
params.gaussianSigma = 1;          % stdev (px) for optional Gaussian smoothing
params.medianKernel  = [3 3];      % kernel size (px) for optional median filtering
params.useCLAHE = true;            % local contrast enhancement toggle
params.claheClipLimit = 0.01;      % [TUNE FIRST] higher = more local contrast/noise
params.claheNumTiles  = [8 8];     % CLAHE tile grid

% ---- 3a. Tissue / background separation -----------------------------------
params.tissueThresholdMethod = 'otsu'; % 'otsu' | 'manual'
params.tissueManualThreshold = 0.2;    % used only if method = 'manual' (0-1 scale)
params.minTissueAreaPx = 500;          % remove tissue speckle smaller than this (px^2)

% ---- 3b. Glomerulus detection ----------------------------------------------
params.glomTextureWindow       = 9;    % odd window size (px) for local texture (stdfilt)
params.glomIntensityPercentile = 80;   % [TUNE FIRST] phase/intensity percentile (within
                                        % tissue) above which a pixel is "glomerulus-like"
params.glomTexturePercentile   = 70;   % [TUNE FIRST] texture percentile threshold
params.glomCloseRadius         = 3;    % morphological closing radius to merge candidate pixels
params.useActiveContourRefinement = true; % refine candidate glomerulus boundary (Chan-Vese)
params.activeContourIterations = 100;
params.glomAreaMinPx  = 300;    % [TUNE FIRST] min glomerulus area in px^2 (depends on
                                % magnification/pixel size - check this FIRST if nothing
                                % is detected)
params.glomAreaMaxPx  = 20000; % [TUNE FIRST] max glomerulus area in px^2
params.glomCircularityMin  = 0.5;  % [TUNE FIRST] 4*pi*Area/Perimeter^2, 1 = perfect circle
params.glomWatershedSuppression = 2; % imextendedmin "H" - raise if glomeruli over-split,
                                      % lower if touching glomeruli are not separated
params.glomRingWidthPx = 15;   % width (px) of the surrounding-tissue ring used to compute
                                % "phase difference relative to surrounding tissue"

% ---- 3c. Renal tubule detection --------------------------------------------
params.tubuleCloseRadius = 2;
params.tubuleAreaMinPx = 150;         % [TUNE FIRST]
params.tubuleAreaMaxPx = 15000;       % [TUNE FIRST]
params.tubuleCircularityMin = 0.3;    % [TUNE FIRST] tubules are often less circular than
                                       % glomeruli, especially if cut obliquely
params.tubuleWatershedSuppression = 2;

% ---- 3d. Tubular lumen detection -------------------------------------------
params.lumenIntensityPercentile = 30; % [TUNE FIRST] pixels below this percentile of a
                                       % tubule's own phase distribution seed the lumen
                                       % region-growing step
params.lumenGrowToleranceFactor = 1.3; % how far region growing is allowed to expand
                                        % beyond the seed threshold (relative)
params.lumenOpenRadius = 1;
params.lumenMinAreaFraction = 0.02;   % minimum lumen area as a fraction of tubule area

% ---- 6. ROI tool -----------------------------------------------------------
params.roiPointRadiusPx = 5;          % radius (px) of the disk used for a "click" (point) ROI
end


%% ========================================================================
%  2. PREPROCESSING
%  ========================================================================
function pre = preprocessQPIImage(rawImage, params)
% PREPROCESSQPIIMAGE  Prepares an image for segmentation while keeping the
% ORIGINAL data (pre.phaseOrig) untouched for all quantitative measurements.
%
% WHY EACH STEP IS NEEDED:
%  - Normalization: puts arbitrary-range intensity/phase values onto a
%    common [0,1] scale so morphological/threshold parameters behave
%    consistently across images.
%  - Background subtraction (morphological opening): QPI phase maps often
%    contain a slowly varying background trend (uneven illumination or
%    optical path length drift) that is much larger in spatial scale than
%    a glomerulus/tubule; opening with a large structuring element
%    estimates this trend so it can be removed without touching the
%    smaller structures of interest.
%  - Optional Gaussian/median filtering: suppresses pixel-level sensor/
%    speckle noise before thresholding.
%  - CLAHE (adaptive histogram equalization): boosts LOCAL contrast so
%    glomeruli/tubules with subtle phase differences from stroma remain
%    separable even under global intensity variation across the tissue.

phaseOrig = rawImage; % keep untouched - used by all Section 5/6 measurements

imgMin = min(rawImage(:));
imgMax = max(rawImage(:));
if imgMax > imgMin
    normImage = (rawImage - imgMin) / (imgMax - imgMin);
else
    normImage = zeros(size(rawImage));
end

se = strel('disk', params.backgroundMorphRadius);
background = imopen(normImage, se);
bgSubtracted = normImage - background;
bgSubtracted = bgSubtracted - min(bgSubtracted(:));
mx = max(bgSubtracted(:));
if mx > 0
    bgSubtracted = bgSubtracted / mx;
end

filtered = bgSubtracted;
switch lower(params.denoiseMethod)
    case 'gaussian'
        filtered = imgaussfilt(filtered, params.gaussianSigma);
    case 'median'
        filtered = medfilt2(filtered, params.medianKernel);
    otherwise
        % 'none' - no denoising applied
end

if params.useCLAHE
    claheImg = adapthisteq(filtered, 'ClipLimit', params.claheClipLimit, ...
        'NumTiles', params.claheNumTiles);
else
    claheImg = filtered;
end

pre.phaseOrig    = phaseOrig;   % original units - use for ALL quantitative measurements
pre.normImage    = normImage;   % [0,1] normalized (display only)
pre.background   = background;  % estimated background trend
pre.bgSubtracted = bgSubtracted;
pre.filtered     = filtered;
pre.claheImg     = claheImg;    % final image used for ALL segmentation steps
end


%% ========================================================================
%  3a. TISSUE / BACKGROUND SEGMENTATION
%  ========================================================================
function tissueMask = segmentTissue(pre, params)
% SEGMENTTISSUE  Separates tissue from empty background/mounting medium.
% WHY: every downstream detector (glomerulus/tubule) restricts its search
% to real tissue, both to save time and to avoid false positives in
% background noise.

img = pre.claheImg;

switch lower(params.tissueThresholdMethod)
    case 'manual'
        level = params.tissueManualThreshold;
    otherwise % 'otsu'
        level = graythresh(img);
end

tissueMask = imbinarize(img, level);
if params.invertTissueMask
    tissueMask = ~tissueMask;
end

% Morphological cleanup: remove speckle, close small internal gaps, fill holes
tissueMask = imopen(tissueMask, strel('disk', 2));
tissueMask = imfill(tissueMask, 'holes');
tissueMask = bwareaopen(tissueMask, params.minTissueAreaPx);
end


%% ========================================================================
%  3b. GLOMERULUS DETECTION
%  ========================================================================
function glomLabels = detectGlomeruli(pre, tissueMask, params)
% DETECTGLOMERULI  Candidate glomeruli are identified as tissue regions
% that are simultaneously (a) high phase/intensity, and (b) high local
% texture (dense packed cell nuclei of the glomerular tuft scatter/
% dephase light more heterogeneously than surrounding tubular epithelium),
% then filtered by area and circularity, and finally split apart with a
% marker-controlled watershed transform where multiple glomeruli touch.
% An optional active-contour (Chan-Vese) step lets the boundary snap to
% the true phase edge instead of the coarse threshold outline.

img = pre.claheImg;

% --- texture: local standard deviation highlights cellular/nuclear density ---
texture = stdfilt(img, true(params.glomTextureWindow));
texture = mat2gray(texture);

tissueVals = img(tissueMask);
textureVals = texture(tissueMask);
if isempty(tissueVals)
    glomLabels = zeros(size(img));
    return;
end
intThresh = prctile(tissueVals, params.glomIntensityPercentile);
texThresh = prctile(textureVals, params.glomTexturePercentile);

candidate = tissueMask & (img >= intThresh) & (texture >= texThresh);

% --- consolidate candidate blobs ---
candidate = imclose(candidate, strel('disk', params.glomCloseRadius));
candidate = imfill(candidate, 'holes');
candidate = bwareaopen(candidate, params.glomAreaMinPx);

% --- optional active-contour boundary refinement ---
if params.useActiveContourRefinement && any(candidate(:))
    candidate = activecontour(img, candidate, params.activeContourIterations, 'Chan-vese');
end

if ~any(candidate(:))
    glomLabels = zeros(size(img));
    return;
end

% --- marker-controlled watershed to separate touching glomeruli ---
D = -bwdist(~candidate);
markerMask = imextendedmin(D, params.glomWatershedSuppression);
D2 = imimposemin(D, markerMask);
Lws = watershed(D2);
candidate(Lws == 0) = 0;

% --- filter by area and circularity (4*pi*Area/Perimeter^2) ---
CC = bwconncomp(candidate);
stats = regionprops(CC, 'Area', 'Perimeter');
keepIdx = [];
for i = 1:CC.NumObjects
    area = stats(i).Area;
    circVal = 4 * pi * area / (stats(i).Perimeter^2 + eps);
    if area >= params.glomAreaMinPx && area <= params.glomAreaMaxPx && ...
            circVal >= params.glomCircularityMin
        keepIdx(end+1) = i; %#ok<AGROW>
    end
end

L = labelmatrix(CC);
keepMask = ismember(L, keepIdx);
glomLabels = bwlabel(keepMask);
end


%% ========================================================================
%  3c. RENAL TUBULE DETECTION
%  ========================================================================
function tubuleLabels = detectTubules(pre, tissueMask, glomLabels, params)
% DETECTTUBULES  Renal tubule cross-sections are detected as compact,
% roughly-round connected components of tissue that are NOT part of a
% glomerulus. Connected-component analysis + morphological cleanup finds
% candidate blobs; a marker-controlled watershed separates tubules that
% touch each other; area and circularity filter out non-tubule debris.

img = pre.claheImg;
nonGlom = tissueMask & (glomLabels == 0);

if ~any(nonGlom(:))
    tubuleLabels = zeros(size(img));
    return;
end

level = graythresh(img(nonGlom));
tubCandidate = nonGlom & imbinarize(img, level);
tubCandidate = imclose(tubCandidate, strel('disk', params.tubuleCloseRadius));
tubCandidate = imfill(tubCandidate, 'holes');
tubCandidate = bwareaopen(tubCandidate, params.tubuleAreaMinPx);

if ~any(tubCandidate(:))
    tubuleLabels = zeros(size(img));
    return;
end

D = -bwdist(~tubCandidate);
markerMask = imextendedmin(D, params.tubuleWatershedSuppression);
D2 = imimposemin(D, markerMask);
Lws = watershed(D2);
tubCandidate(Lws == 0) = 0;

CC = bwconncomp(tubCandidate);
stats = regionprops(CC, 'Area', 'Perimeter');
keepIdx = [];
for i = 1:CC.NumObjects
    area = stats(i).Area;
    circVal = 4 * pi * area / (stats(i).Perimeter^2 + eps);
    if area >= params.tubuleAreaMinPx && area <= params.tubuleAreaMaxPx && ...
            circVal >= params.tubuleCircularityMin
        keepIdx(end+1) = i; %#ok<AGROW>
    end
end

L = labelmatrix(CC);
keepMask = ismember(L, keepIdx);
tubuleLabels = bwlabel(keepMask);
end


%% ========================================================================
%  3d. TUBULAR LUMEN DETECTION
%  ========================================================================
function lumenLabels = detectLumens(pre, tubuleLabels, params)
% DETECTLUMENS  For each detected tubule, the lumen is the open central
% space - lower phase/intensity than the surrounding epithelial wall.
% A REGION-GROWING approach (morphological reconstruction, imreconstruct)
% is used: a conservative "seed" of very-low-phase pixels is grown to
% include adjacent moderately-low-phase pixels, which is more robust to
% partial-volume/noisy pixels than a single hard percentile cut.
%
% lumenLabels shares the SAME numeric IDs as tubuleLabels (i.e. lumen
% pixels belonging to tubule #t are labeled "t", not re-numbered), which
% makes it trivial to pair each tubule with its own lumen in
% calculateTubularFeatures.

img = pre.claheImg;
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
    grown = imreconstruct(seed, growLimit); % region growing via morphological reconstruction

    grown = imopen(grown, strel('disk', params.lumenOpenRadius));
    grown = bwareaopen(grown, max(1, round(params.lumenMinAreaFraction * nnz(tubMask))));

    % Enforce "enclosed" - lumen must not touch the tubule's outer rim
    outerRim = tubMask & ~imerode(tubMask, strel('disk', 1));
    grown = grown & ~imdilate(outerRim, strel('disk', 1));

    lumenLabels(grown) = t;
end
end


%% ========================================================================
%  5. QUANTITATIVE ANALYSIS - GLOMERULI
%  ========================================================================
function glomTable = calculateGlomerularFeatures(glomLabels, pre, tissueMask, params)
% CALCULATEGLOMERULARFEATURES  Computes, per detected glomerulus:
% Area, EquivDiameter, Circularity (4*pi*Area/Perimeter^2), MeanPhase,
% StdPhase, and PhaseDiffSurrounding (mean glomerulus phase minus mean
% phase of a ring of surrounding tissue, excluding the glomerulus itself).
% All phase statistics use pre.phaseOrig (ORIGINAL units), never the
% normalized/CLAHE image used only for segmentation.

img = pre.phaseOrig;
px = params.pixelSize;
n = max(glomLabels(:));

ID = []; Area_um2 = []; EquivDiam_um = []; Circularity = [];
MeanPhase = []; StdPhase = []; PhaseDiffSurrounding = [];

for i = 1:n
    m = glomLabels == i;
    if ~any(m(:)); continue; end

    s = regionprops(m, 'Area', 'Perimeter', 'EquivDiameter');
    area = s(1).Area;
    circVal = 4 * pi * area / (s(1).Perimeter^2 + eps);

    ring = imdilate(m, strel('disk', params.glomRingWidthPx)) & ~m & tissueMask;
    glomVals = img(m);
    ringVals = img(ring);

    ID(end+1,1) = i; %#ok<AGROW>
    Area_um2(end+1,1) = area * px^2; %#ok<AGROW>
    EquivDiam_um(end+1,1) = s(1).EquivDiameter * px; %#ok<AGROW>
    Circularity(end+1,1) = circVal; %#ok<AGROW>
    MeanPhase(end+1,1) = mean(glomVals); %#ok<AGROW>
    StdPhase(end+1,1) = std(glomVals); %#ok<AGROW>
    if isempty(ringVals)
        PhaseDiffSurrounding(end+1,1) = NaN; %#ok<AGROW>
    else
        PhaseDiffSurrounding(end+1,1) = mean(glomVals) - mean(ringVals); %#ok<AGROW>
    end
end

glomTable = table(ID, Area_um2, EquivDiam_um, Circularity, MeanPhase, StdPhase, PhaseDiffSurrounding);
end


%% ========================================================================
%  5. QUANTITATIVE ANALYSIS - TUBULES
%  ========================================================================
function tubTable = calculateTubularFeatures(tubuleLabels, lumenLabels, pre, params)
% CALCULATETUBULARFEATURES  Computes, per detected tubule: TubuleArea,
% LumenArea, LumenRatio (=Lumen area/Tubule area), estimated
% WallThickness, Circularity, MeanWallPhase, MeanLumenPhase, and
% WallLumenPhaseDiff.
%
% WallThickness is estimated from equivalent diameters,
% (EquivDiameter_tubule - EquivDiameter_lumen)/2, converted to
% micrometers. This is a robust average-radial-thickness APPROXIMATION;
% for very irregular (non-round) tubules it under/over-estimates local
% thickness variation - treat it as a mean, not a per-point measurement.

img = pre.phaseOrig;
px = params.pixelSize;
n = max(tubuleLabels(:));

ID = []; TubuleArea_um2 = []; LumenArea_um2 = []; LumenRatio = [];
WallThickness_um = []; Circularity = []; MeanWallPhase = [];
MeanLumenPhase = []; WallLumenPhaseDiff = [];

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
        wallThick = max((sT(1).EquivDiameter - sL(1).EquivDiameter) / 2, 0) * px;
        meanLumenPhase = mean(img(lumMask));
    else
        wallThick = NaN;
        meanLumenPhase = NaN;
    end
    meanWallPhase = mean(img(wallMask));

    ID(end+1,1) = t; %#ok<AGROW>
    TubuleArea_um2(end+1,1) = tArea * px^2; %#ok<AGROW>
    LumenArea_um2(end+1,1) = lArea * px^2; %#ok<AGROW>
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
%  4. VISUALIZATION - COLOR OVERLAY
%  ========================================================================
function overlay = createOverlay(baseImg, tissueMask, glomLabels, tubuleLabels, lumenLabels) %#ok<INUSD>
% CREATEOVERLAY  Builds an RGB overlay: glomerulus=red, tubule=green,
% lumen=blue, background left as plain grayscale (transparent = no tint).

base = mat2gray(baseImg);
overlay = repmat(base, 1, 1, 3);
alpha = 0.45;

glomMask = glomLabels > 0;
lumMask  = lumenLabels > 0;
tubMask  = (tubuleLabels > 0) & ~glomMask & ~lumMask;

overlay = blendColor(overlay, glomMask, [1 0 0], alpha);
overlay = blendColor(overlay, tubMask,  [0 1 0], alpha);
overlay = blendColor(overlay, lumMask,  [0 0 1], alpha);
end

function ov = blendColor(ov, mask, color, alpha)
% BLENDCOLOR  Alpha-blends a flat RGB color into ov wherever mask is true.
for c = 1:3
    ch = ov(:,:,c);
    ch(mask) = (1 - alpha) * ch(mask) + alpha * color(c);
    ov(:,:,c) = ch;
end
end


%% ========================================================================
%  ONE-IMAGE PIPELINE (preprocessing -> segmentation -> measurement)
%  ========================================================================
function result = analyzeOneImage(imgInfo, params, interactive)
% ANALYZEONEIMAGE  Runs the full Section 2-5 pipeline for a single image,
% optionally offering manual correction and the interactive dashboard
% (Section 6/7) when interactive == true.

params.pixelSize = imgInfo.pixelSize;

pre = preprocessQPIImage(imgInfo.rawImage, params);
tissueMask   = segmentTissue(pre, params);
glomLabels   = detectGlomeruli(pre, tissueMask, params);
tubuleLabels = detectTubules(pre, tissueMask, glomLabels, params);
lumenLabels  = detectLumens(pre, tubuleLabels, params);

if interactive
    choice = questdlg(['Automatic segmentation is a classical-image-processing ' ...
        'estimate and may miss or mis-shape structures. Does it look OK, or would ' ...
        'you like to open the manual correction tool?'], ...
        'Review Segmentation', 'Looks good', 'Manual Correction', 'Looks good');
    if strcmp(choice, 'Manual Correction')
        [glomLabels, tubuleLabels, lumenLabels] = manualCorrectionUI(pre, tissueMask, ...
            glomLabels, tubuleLabels, lumenLabels);
    end
end

glomTable = calculateGlomerularFeatures(glomLabels, pre, tissueMask, params);
tubTable  = calculateTubularFeatures(tubuleLabels, lumenLabels, pre, params);
overlay   = createOverlay(pre.claheImg, tissueMask, glomLabels, tubuleLabels, lumenLabels);

result.pre          = pre;
result.tissueMask   = tissueMask;
result.glomLabels    = glomLabels;
result.tubuleLabels  = tubuleLabels;
result.lumenLabels   = lumenLabels;
result.glomTable     = glomTable;
result.tubTable      = tubTable;
result.overlay       = overlay;
result.imgInfo       = imgInfo;
result.params        = params;

if interactive
    showDashboard(imgInfo, result, params);
end
end


%% ========================================================================
%  6. MANUAL / SEMI-AUTOMATIC CORRECTION
%  ========================================================================
function [glomLabels, tubuleLabels, lumenLabels] = manualCorrectionUI(pre, tissueMask, ...
    glomLabels, tubuleLabels, lumenLabels)
% MANUALCORRECTIONUI  Classical image processing without training data
% cannot guarantee correct glomerulus/tubule detection on every image -
% textures, staining/phase contrast, and tissue orientation vary a lot.
% This tool lets you fix the automatic result by hand:
%   - draw a polygon to ADD a missed glomerulus or tubule
%   - click inside a region to REMOVE a false-positive glomerulus or tubule
% All Section 5 measurements are recomputed from whatever mask exists
% after correction, so manually drawn regions are treated identically to
% automatically detected ones.

while true
    choice = menu('Manual / Semi-Automatic Correction', ...
        'Add glomerulus (draw polygon)', 'Remove glomerulus (click inside)', ...
        'Add tubule (draw polygon)', 'Remove tubule (click inside)', ...
        'Done - return to results');

    switch choice
        case 1
            f = figure('Name', 'Draw new glomerulus boundary - double-click to finish');
            imshow(createOverlay(pre.claheImg, tissueMask, glomLabels, tubuleLabels, lumenLabels));
            h = drawpolygon('Color', 'r');
            wait(h);
            newMask = createMask(h);
            newID = max(glomLabels(:)) + 1;
            glomLabels(newMask) = newID;
            close(f);

        case 2
            f = figure('Name', 'Click inside the glomerulus you want to remove');
            imshow(createOverlay(pre.claheImg, tissueMask, glomLabels, tubuleLabels, lumenLabels));
            [x, y] = ginput(1);
            id = glomLabels(max(1,round(y)), max(1,round(x)));
            if id > 0
                glomLabels(glomLabels == id) = 0;
            end
            close(f);

        case 3
            f = figure('Name', 'Draw new tubule boundary - double-click to finish');
            imshow(createOverlay(pre.claheImg, tissueMask, glomLabels, tubuleLabels, lumenLabels));
            h = drawpolygon('Color', 'g');
            wait(h);
            newMask = createMask(h);
            newID = max(tubuleLabels(:)) + 1;
            tubuleLabels(newMask) = newID;
            close(f);

        case 4
            f = figure('Name', 'Click inside the tubule you want to remove');
            imshow(createOverlay(pre.claheImg, tissueMask, glomLabels, tubuleLabels, lumenLabels));
            [x, y] = ginput(1);
            id = tubuleLabels(max(1,round(y)), max(1,round(x)));
            if id > 0
                tubuleLabels(tubuleLabels == id) = 0;
                lumenLabels(lumenLabels == id) = 0;
            end
            close(f);

        otherwise
            break;
    end
end
end


%% ========================================================================
%  6. ROI INTERACTION
%  ========================================================================
function analyzeROI(pre, params)
% ANALYZEROI  Lets the user click (point) or draw (rectangle/freehand/
% polygon) a region of interest, then reports mean/median/std/min/max
% phase, a histogram, and horizontal/vertical phase profiles through the
% ROI's center. Always computed on pre.phaseOrig (original units).

img = pre.phaseOrig;

shape = menu('Select ROI type', 'Point (click)', 'Rectangle', 'Freehand', 'Polygon');
if shape == 0; return; end

fSel = figure('Name', 'Draw / click your ROI', 'NumberTitle', 'off');
imshow(mat2gray(img));
title('Select ROI, then double-click (or right-click > Finish) to confirm');

switch shape
    case 1
        [x, y] = ginput(1);
        [xx, yy] = meshgrid(1:size(img,2), 1:size(img,1));
        roiMask = (xx - x).^2 + (yy - y).^2 <= params.roiPointRadiusPx^2;
        roiOutlineXY = [x + params.roiPointRadiusPx*cos(0:0.1:2*pi); ...
                        y + params.roiPointRadiusPx*sin(0:0.1:2*pi)]';
    case 2
        h = drawrectangle('Color', 'y'); wait(h);
        roiMask = createMask(h);
        roiOutlineXY = h.Position; % [x y w h], handled generically below
    case 3
        h = drawfreehand('Color', 'y'); wait(h);
        roiMask = createMask(h);
        roiOutlineXY = h.Position;
    otherwise
        h = drawpolygon('Color', 'y'); wait(h);
        roiMask = createMask(h);
        roiOutlineXY = h.Position;
end
close(fSel);

if ~any(roiMask(:))
    warndlg('Empty ROI - nothing to analyze.', 'ROI Analysis');
    return;
end

vals = img(roiMask);
statsStr = sprintf(['ROI Statistics:  Mean = %.4f | Median = %.4f | Std = %.4f | ' ...
    'Min = %.4f | Max = %.4f | N = %d px'], ...
    mean(vals), median(vals), std(vals), min(vals), max(vals), numel(vals));
disp(statsStr);

props = regionprops(roiMask, 'Centroid', 'BoundingBox');
c = round(props(1).Centroid);
bbox = props(1).BoundingBox;
rowRange = max(1, round(bbox(2))):min(size(img,1), round(bbox(2) + bbox(4)));
colRange = max(1, round(bbox(1))):min(size(img,2), round(bbox(1) + bbox(3)));

figure('Name', 'ROI Results', 'NumberTitle', 'off', 'Position', [100 100 900 700]);

subplot(2,2,1);
imshow(mat2gray(img)); hold on;
if shape == 1
    plot(roiOutlineXY(:,1), roiOutlineXY(:,2), 'y-', 'LineWidth', 1.5);
elseif shape == 2
    rectangle('Position', roiOutlineXY, 'EdgeColor', 'y', 'LineWidth', 1.5);
else
    plot([roiOutlineXY(:,1); roiOutlineXY(1,1)], [roiOutlineXY(:,2); roiOutlineXY(1,2)], ...
        'y-', 'LineWidth', 1.5);
end
title('ROI location');

subplot(2,2,2);
histogram(vals, 30);
title('ROI Phase Histogram'); xlabel('Phase value'); ylabel('Pixel count');

subplot(2,2,3);
plot(colRange, img(c(2), colRange), 'b-', 'LineWidth', 1.2);
title('Horizontal profile through ROI center'); xlabel('x (px)'); ylabel('Phase');
xline(c(1), '--k');

subplot(2,2,4);
plot(rowRange, img(rowRange, c(1)), 'r-', 'LineWidth', 1.2);
title('Vertical profile through ROI center'); xlabel('y (px)'); ylabel('Phase');
xline(c(2), '--k');

sgtitle(statsStr, 'FontSize', 9);
end


%% ========================================================================
%  7. RESULTS DASHBOARD (Sections 4 + 7 display, tables, controls)
%  ========================================================================
function showDashboard(imgInfo, result, params)
% SHOWDASHBOARD  Displays the original/preprocessed/mask/overlay/boundary
% panels (Section 4), the measurement tables in uitable (Section 7), and
% a small control panel with ROI Analysis / Manual Correction / Export
% buttons.

pre = result.pre;

fig1 = figure('Name', ['Kidney QPI Analysis - ' imgInfo.name], 'NumberTitle', 'off', ...
    'Position', [50 50 1400 800]);

subplot(2,3,1); imshow(mat2gray(imgInfo.rawImage)); title('1. Original image');

subplot(2,3,2); imshow(pre.claheImg); title('2. Preprocessed image');

maskCode = double(result.tissueMask) + 2*double(result.glomLabels > 0) + ...
    3*double(result.tubuleLabels > 0 & result.glomLabels == 0);
subplot(2,3,3); imshow(label2rgb(maskCode, 'jet', 'k')); title('3. Segmentation mask');

subplot(2,3,4); imshow(result.overlay);
title('4. Color overlay (R=glomerulus  G=tubule  B=lumen)');

subplot(2,3,5);
imshow(mat2gray(pre.claheImg)); hold on;
if any(result.glomLabels(:) > 0)
    visboundaries(result.glomLabels > 0, 'Color', 'r');
end
if any(result.tubuleLabels(:) > 0)
    visboundaries(result.tubuleLabels > 0 & result.glomLabels == 0, 'Color', 'g');
end
if any(result.lumenLabels(:) > 0)
    visboundaries(result.lumenLabels > 0, 'Color', 'b');
end
title('Boundaries');

subplot(2,3,6);
imshow(mat2gray(pre.claheImg)); hold on;
sG = regionprops(result.glomLabels, 'Centroid');
for i = 1:numel(sG)
    if ~isempty(sG(i).Centroid)
        text(sG(i).Centroid(1), sG(i).Centroid(2), sprintf('G%d', i), ...
            'Color', 'r', 'FontWeight', 'bold', 'FontSize', 8);
    end
end
sT = regionprops(result.tubuleLabels, 'Centroid');
for i = 1:numel(sT)
    if ~isempty(sT(i).Centroid)
        text(sT(i).Centroid(1), sT(i).Centroid(2), sprintf('T%d', i), ...
            'Color', 'g', 'FontWeight', 'bold', 'FontSize', 8);
    end
end
title('Object IDs (G=glomerulus, T=tubule)');

fig2 = figure('Name', 'Glomerulus Measurements', 'NumberTitle', 'off', ...
    'Position', [100 80 950 260]);
uitable(fig2, 'Data', table2cell(result.glomTable), ...
    'ColumnName', result.glomTable.Properties.VariableNames, ...
    'Units', 'normalized', 'Position', [0 0 1 1]);

fig3 = figure('Name', 'Tubule Measurements', 'NumberTitle', 'off', ...
    'Position', [100 380 950 260]);
uitable(fig3, 'Data', table2cell(result.tubTable), ...
    'ColumnName', result.tubTable.Properties.VariableNames, ...
    'Units', 'normalized', 'Position', [0 0 1 1]);

fig4 = figure('Name', 'Controls', 'NumberTitle', 'off', 'Position', [1470 80 260 260], ...
    'MenuBar', 'none', 'ToolBar', 'none');
uicontrol(fig4, 'Style', 'pushbutton', 'String', 'ROI Analysis', ...
    'Units', 'normalized', 'Position', [0.1 0.72 0.8 0.2], ...
    'Callback', @(~,~) analyzeROI(pre, params));
uicontrol(fig4, 'Style', 'pushbutton', 'String', 'Manual Correction', ...
    'Units', 'normalized', 'Position', [0.1 0.40 0.8 0.2], ...
    'Callback', @(~,~) rerunCorrection());
uicontrol(fig4, 'Style', 'pushbutton', 'String', 'Export Results', ...
    'Units', 'normalized', 'Position', [0.1 0.08 0.8 0.2], ...
    'Callback', @(~,~) doExport());

    function rerunCorrection()
        [g, t, l] = manualCorrectionUI(pre, result.tissueMask, ...
            result.glomLabels, result.tubuleLabels, result.lumenLabels);
        result.glomLabels = g; result.tubuleLabels = t; result.lumenLabels = l;
        result.glomTable = calculateGlomerularFeatures(g, pre, result.tissueMask, params);
        result.tubTable  = calculateTubularFeatures(t, l, pre, params);
        result.overlay   = createOverlay(pre.claheImg, result.tissueMask, g, t, l);
        if isvalid(fig1); close(fig1); end
        if isvalid(fig2); close(fig2); end
        if isvalid(fig3); close(fig3); end
        if isvalid(fig4); close(fig4); end
        showDashboard(imgInfo, result, params);
    end

    function doExport()
        outDir = uigetdir(pwd, 'Select folder to export results');
        if isequal(outDir, 0); return; end
        exportResults(outDir, imgInfo.name, result);
        msgbox(['Exported to ' outDir], 'Export Complete');
    end
end


%% ========================================================================
%  7. EXPORT RESULTS
%  ========================================================================
function exportResults(outDir, baseName, result)
% EXPORTRESULTS  Saves the overlay image (PNG), all masks (MAT), and the
% glomerulus/tubule measurement tables (CSV and, if supported, XLSX) to
% outDir.

if ~exist(outDir, 'dir'); mkdir(outDir); end
[~, nm] = fileparts(baseName);

imwrite(result.overlay, fullfile(outDir, [nm '_overlay.png']));

tissueMask   = result.tissueMask;   %#ok<NASGU>
glomLabels   = result.glomLabels;   %#ok<NASGU>
tubuleLabels = result.tubuleLabels; %#ok<NASGU>
lumenLabels  = result.lumenLabels;  %#ok<NASGU>
save(fullfile(outDir, [nm '_masks.mat']), 'tissueMask', 'glomLabels', 'tubuleLabels', 'lumenLabels');

writetable(result.glomTable, fullfile(outDir, [nm '_glomeruli.csv']));
writetable(result.tubTable,  fullfile(outDir, [nm '_tubules.csv']));

try
    writetable(result.glomTable, fullfile(outDir, [nm '_glomeruli.xlsx']));
    writetable(result.tubTable,  fullfile(outDir, [nm '_tubules.xlsx']));
catch
    % Excel export can fail on systems without Excel/COM support (e.g. some
    % Linux/macOS setups) - CSV files above are already saved as a fallback.
end
end
