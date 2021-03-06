function HighPrecisionLuminanceOutputDriversImagingPipelineTest(whichDriver, whichScreen, plotdiffs, forcesuccess)
% HighPrecisionLuminanceOutputDriversImagingPipelineTest(whichDriver, [whichScreen][,plotdiffs=0][, forcesuccess=0])
%
% Tests correct function of a variety of high precision luminance output
% device drivers (so called "output formatters") with imaging pipeline.
%
% This test script needs to be run once after each graphics card or
% graphics driver or Psychtoolbox upgrade, or after any other major change
% in system configuration and display settings.
%
% This test verifies that the Psychtoolbox image processing pipeline is
% capable to correctly convert a high dynamic range / high bit precision
% luminance image into a output format suitable for driving one of the
% supported high precision luminance output devices, e.g., different Pelli,
% Zhang, Watson style video attenuators, Xiangru Li et al. VideoSwitchers,
% Pseudo-Gray output formatters, etc.
%
% It does so by generating a test stimulus, converting it into a properly
% formatted image via the "known good" Matlab reference implementation of
% an output driver, then again via the  use of the imaging pipeline. Then
% it reads back and compares the conversion results of both to verify that
% the imaging pipeline produces exactly the same results as the Matlab
% routines.
%
% If the results are the same, it will write some info file to the
% filesystem to confirm this test was successfully run, otherwise it will
% fail with a description of the discrepancy. In case of failure, fast
% stimulus conversion will not work via the imaging pipeline.
%
% The required parameter 'whichDriver' defines the type of output driver to
% test. It can be any of the following:
%
% * 'GenericLUT': Test the generic lookup-table based driver that can handle
% arbitrary devices, albeit not with maximum speed. 'whichDriver' must be a
% struct with the following fields:
%
% whichDriver.name = 'GenericLUT'
%
% Then either one of these for testing of a generic LUT:
%
% whichDriver.bpc = Bitdepths of LUT to test - Anything between 1 and 16.
% whichDriver.nslots = Size of LUT in slots - Anything between 2 and 65536.
%
% Alternatively you can test with an existing self-created LUT:
% whichDriver.lut = A 3 rows by nslots column uint8 matrix which encodes
% the LUT: Rows 1,2 and 3 encode Red, Green and Blue channel, each of the
% 'nslots' columns encodes a LUT slot. The driver will map luminance values
% between 0.0 and 1.0 to the corresponding LUT slots in range 1 to nslots,
% then readout the stored column vector with the output RGBA8 pixels to
% poke into the framebuffer.
%
% * 'VideoSwitcherSimple': Test the "simple" driver for the VideoSwitcher
% video attenuator. The simple driver implements a closed-form solution, a
% formula, to map luminance values between 0.0 - 1.0 to output values for
% the Red and Blue channel, just using the 'BTRR' ratio as parameter. This
% is the fast driver, as it doesn't need any lookup tables.
% 
% You should provide the whichDriver.btrr BTRR ratio when testing this
% driver. If you omit it, it will be loaded from the configuration file in
% the Psychtoolbox configuration directory.
%
% * 'VideoSwitcherCalibrated': Test the LUT based driver for the VideoSwitcher
% video attenuator. This driver computes the Blue channel value by
% searching for the given luminance value in a 256 entry lookup table, then
% uses a closed-form formula to compute the Red channel drive value from
% the luminance and the looked-up blue channel value. This is slower due to table
% lookups and requires more involved calibration procedures to build a
% lookup table, but it is also potentially more accurate.
%
% You should provide the whichDriver.btrr BTRR ratio when testing this
% driver, as well as the 257 slot whichDriver.lut lookup table for blue
% channel to measured luminance mapping. See help PsychVideoSwitcher for
% more info. If you omit these parameters, a default BTRR and LUT will be
% loaded from the Psychtoolbox configuration subdirectory.
%
% Optional parameters:
%
% whichScreen  = Screen id of display to test on. Will be the secondardy
%                display if none provided.
%
% plotdiffs    = If set to one, plot diagnostic difference images, if any
%                differences are detected. By default no such images are
%                plotted. No images will be plotted if no differences
%                exist.
%
% forcesuccess = Set this to one if you want to force the test to succeed,
%                despite detected errors, ie., if you want the GPU
%                conversion to be used. Only use this if you really know
%                what you are doing!
%
% Please note that this test script can only test if the correct output to
% your systems framebuffer is generated by Psychtoolbox. It can't detect if
% the electronic high precision converter device itself is working
% correctly with this data. Only visual inspection and a
% photometer/colorimeter test can really tell you if the whole system is
% working correctly!
%

% History:
% 05/24/08 mk    Initial implementation.

oldverbosity = Screen('Preference', 'Verbosity', 2);
oldsynclevel = Screen('Preference', 'SkipSyncTests', 2);

% Which driver to test?
if nargin < 1 || isempty(whichDriver)
    error('You must provide a valid "whichDriver" argument!');
end

% Define screen:
if nargin < 2 || isempty(whichScreen)
    whichScreen=max(Screen('Screens'));
end

if nargin < 3 || isempty(plotdiffs)
    plotdiffs = 0;
end

if nargin < 4 || isempty(forcesuccess)
    forcesuccess = 0;
end

if isstruct(whichDriver)
    % Extract 'bpc' subfield, if any:
    if isfield(whichDriver, 'bpc')
        driverBpc = whichDriver.bpc;
        if ~isscalar(driverBpc) || driverBpc < 1 || driverBpc > 16
            error('"whichDriver.bpc" argument is not a integral bitdepths value in valid range 1 - 16!');
        end
    else
        driverBpc = [];
    end
    
    % Extract 'nslots' subfield, if any:
    if isfield(whichDriver, 'nslots')
        driverNSlots = whichDriver.nslots;
        if ~isscalar(driverNSlots) || driverNSlots < 2 || driverNSlots > 2^16
            error('"whichDriver.nslots" argument is not an integral value in valid range 2 - 65536!');
        end
    else
        driverNSlots = [];
    end

    % Extract 'lut' subfield, if any:
    if isfield(whichDriver, 'lut')
        driverLUT = whichDriver.lut;
        if ~isa(driverLUT, 'uint8') || size(driverLUT, 1) < 3 || size(driverLUT, 1) > 4 || size(driverLUT, 2) < 2 || size(driverLUT, 2) > 65536 
            error('"whichDriver.lut" argument is not a LUT definition matrix: Must be a matrix of class uint8 with 3 or 4 rows and between 2 and 65536 columns!');
        end
        
        if size(driverLUT, 1)~=4
            % Extend with 4th row of all zero bytes:
            driverLUT = [driverLUT ; uint8(zeros(1, size(driverLUT, 2)))];
        end
    else
        driverLUT = [];
    end

    % Extract 'bpc' subfield, if any:
    if isfield(whichDriver, 'btrr')
        driverBTRR = whichDriver.btrr;
        if ~isscalar(driverBTRR) || ~isnumeric(driverBTRR) || driverBTRR < 0
            error('"whichDriver.btrr" argument is not a scalar Blue-To-Red-Ratio value greater than zero.');
        end
    else
        driverBTRR = [];
    end

    % This comes last! Check if .name subfield provided and replace whole
    % struct with that name:
    if isfield(whichDriver, 'name')
        whichDriver = whichDriver.name;
    else
        error('Argument "whichDriver" is a struct, but lacks the mandatory subfield "name"!');
    end
else
    driverBpc = [];
    driverNSlots = [];
    driverLUT = [];
    driverBTRR = [];
end

if ~ischar(whichDriver)
    error('"whichDriver" or "whichDriver.name" is not a driver name string!');
end

if isempty(driverNSlots) && ~isempty(driverBpc)
    driverNSlots = 2^driverBpc;
end

if ~isempty(driverLUT)
    driverNSlots = size(driverLUT, 2);
end

% Prepare imaging pipeline setup:
PsychImaging('PrepareConfiguration');

% Make sure we run with our default color correction mode for this test:
% 'ClampOnly' is the default, but we set it here explicitely, so no state
% from previously running scripts can bleed through. This will also setup
% the default clamping range to our wanted 0.0 - 1.0 range:
PsychImaging('AddTask', 'FinalFormatting', 'DisplayColorCorrection', 'ClampOnly');

fprintf('Testing output formatting driver of type: %s\n', whichDriver);
fprintf('Number of slots (if any): %i\n', driverNSlots);
fprintf('Number of bpc bits (if any): %i\n', driverBpc);
fprintf('BTRR (if any): %i\n', driverBTRR);

fprintf('\n\n\n');

% Select whichDriver to test:
switch (whichDriver)
    case {'GenericLUT'}
        % Generic LUT conversion with a LUT that has driverNSlots slots
        % to map the 0.0 - 1.0 input range into 0 - driverNSlots - 1
        % integral range, then lookup the value:
        if isempty(driverNSlots)
            error('Driver type "GenericLUT" selected, but "whichDriver.nslots" argument missing!');
        end
        
        if isempty(driverLUT)
            % Build standard testing LUT with driverNSlots slots for testing:
            lut = uint8(zeros(4, driverNSlots));
            theRange = 0:driverNSlots-1;
            theInverseRange = (driverNSlots-1) - theRange;
            lut(1, 1:driverNSlots) = uint8(floor(theRange/256));                % Red channel: High Byte.
            lut(2, 1:driverNSlots) = uint8(floor(mod(theRange, 256)));          % Green channel: Low Byte.
            lut(3, 1:driverNSlots) = uint8(floor(theInverseRange/256));         % Blue channel: Inverse range High Byte.
            lut(4, 1:driverNSlots) = uint8(floor(mod(theInverseRange, 256)));   % Alpha channel: Inverse range Low Byte.
            plotchannel = [1,1,1,1];
        else
            % LUT provided: Just use it "as is":
            lut = driverLUT;
            plotchannel = [1,1,1,0];
        end
        
        
        % Enable generic LUT luminance output formatter and provide it with
        % our lut:
        PsychImaging('AddTask', 'General', 'EnableGenericHighPrecisionLuminanceOutput', lut);
        
        % Build test image:
        theInImage = reshape(linspace(0, 1, 2^16), 256, 256);
        
        % Build reference image:
        theIntImage = uint32( floor(theInImage * (driverNSlots-1)) );
        theRefImage = zeros(256, 256, 4);
        
        % Recompute theInImage from the theIntImage -- theInImage shall
        % become a quantized version of itself - quantized to
        % driverNSlots-1 levels. This way we can be sure that the GPU and
        % CPU get initially fed with the same data for conversion:
        theInImage = double(theIntImage) / (driverNSlots-1);

        uniqueValsA = length(unique(theInImage));
        uniqueValsB = length(unique(theIntImage));

        if (uniqueValsA~=uniqueValsB) || (uniqueValsA~=driverNSlots)
            fprintf('Ouch! Number of unique test samples in different images is not the same! Bug in test code?!?\n');
            fprintf('Input to GPU (float) = %i, Input to CPU (uint32) = %i, Reference Expected (nr. slots) = %i\n', uniqueValsA, uniqueValsB, driverNSlots);
            error('Mismatch in unique values count! Likely a bug in this test code!');
        end
        
        theRefImage(:,:,1:3) = ind2rgb(theIntImage, double(lut(1:3,:)')); 
        
        % Need to treat alpha channel separately, as ind2rgb can only
        % handle 3 layer images...
        theAlphaImage = ind2rgb(theIntImage, double(repmat(lut(4,:)', 1, 3)));
        theRefImage(:,:,4) = theAlphaImage(:,:,1);

        % Convert to uint8:
        theRefImage = uint8(theRefImage);
        
    case {'VideoSwitcherSimple'}

        % Select simple VideoSwitcher output formatter:
        PsychImaging('AddTask', 'General', 'EnableVideoSwitcherSimpleLuminanceOutput', driverBTRR);
        
        if isempty(driverBTRR)
            % Fetch default from file:
            driverBTRR = PsychVideoSwitcher('GetDefaultConfig', whichScreen);
        end
        
        % Build test image:
        theInImage = reshape(linspace(0, 1, 2^16), 256, 256);
        
        % Build reference image:
        theRefImage = uint8(zeros(256, 256, 4));
        theRefImage(:,:,1:3) = PsychVideoSwitcher('MapLuminanceToRGB', theInImage, driverBTRR, 0);
        plotchannel = [1,0,1,0];

    case {'VideoSwitcherCalibrated'}

        if isempty(driverBTRR) || isempty(driverLUT)
            [mydriverBTRR, mydriverLUT] = PsychVideoSwitcher('GetDefaultConfig', whichScreen);
            if isempty(driverBTRR)
                driverBTRR = mydriverBTRR;
            end
            
            if isempty(driverLUT)
                driverLUT = mydriverLUT;
            end
        end
        
        % Select calibrated VideoSwitcher output formatter:
        PsychImaging('AddTask', 'General', 'EnableVideoSwitcherCalibratedLuminanceOutput', driverBTRR, driverLUT);
        
        % Build test image:
        theInImage = reshape(linspace(0, 1, 2^16), 256, 256);
        
        % Build reference image:
        theRefImage = uint8(zeros(256, 256, 4));
        theRefImage(:,:,1:3) = PsychVideoSwitcher('MapLuminanceToRGBCalibrated', theInImage, driverBTRR, driverLUT, 0);
        plotchannel = [1,0,1,1];

    otherwise
        error('Unknown drivername provided. Not supported! Typo?!?');
end

% Common code for testing:

% Perform GPU conversion and readback results:
[m,n,p] = size(theRefImage);
rect = [0 0 m n];

% Show the image
window = PsychImaging('OpenWindow', whichScreen, 0);

% Double-Check for bugs in PsychImaging:
winfo = Screen('GetWindowInfo', window);
if ~bitand(winfo.ImagingMode, kPsychNeed32BPCFloat)
    Screen('CloseAll');
    RestoreCluts;
    error('Onscreen window not configured for 32 bpc float drawing! This should not happen and is a bug in PsychImaging.m setup code for this formatter!!');
end

% Find out how big the window is:
[screenWidth, screenHeight]=Screen('WindowSize', window);

% Build HDR input texture as 32 bpc float luminance texture:
hdrtexIndex= Screen('MakeTexture', window, double(theInImage), [], [], 2);

% Draw image as generated by PTB GPU imaging pipeline:
dstRect = Screen('Rect', hdrtexIndex);

% Draw with nearest neighbour filtering - no bilinear filtering!
Screen('DrawTexture', window, hdrtexIndex, [], dstRect, [], 0);

% Finalize image before we take a screenshot:
Screen('DrawingFinished', window, 0, 1);

% Take screenshot of GPU converted image:
convImage=Screen('GetImage', window, dstRect, 'backBuffer', 0, 4);

% Show GPU converted image. Should obviously not make any visual difference if
% it is the same as the Matlab converted image.
vbl = Screen('Flip', window);

% Disable output formatters:
Screen('HookFunction', window, 'Disable', 'FinalOutputFormattingBlit');

% Build and draw texture from reference image - This is just for
% visualization, not used for comparison:
texpacked= Screen('MakeTexture', window, theRefImage);
dstRect = Screen('Rect', texpacked);
Screen('DrawTexture', window, texpacked, [], dstRect, [], 0);

% Show it:
vbl = Screen('Flip', window, vbl + 1);

% Keep it onscreen for 2 seconds, then blank screen:
Screen('Flip', window, vbl + 2);

% Done. Close everything down:
Screen('CloseAll');
RestoreCluts;

% Comparisons...

% Compute difference images between Matlab converted packedImage and GPU converted
% HDR image:
diffred   = (double(theRefImage(:,:,1)) - double(convImage(:,:,1)));
diffgreen = (double(theRefImage(:,:,2)) - double(convImage(:,:,2)));
diffblue  = (double(theRefImage(:,:,3)) - double(convImage(:,:,3)));
diffalpha = (double(theRefImage(:,:,4)) - double(convImage(:,:,4)));

% Compute maximum deviation of framebuffer raw data:
mdr = max(max(abs(diffred)));
mdg = max(max(abs(diffgreen)));
mdb = max(max(abs(diffblue)));
mda = max(max(abs(diffalpha)));

fprintf('\n\nMaximum raw data difference: red= %f green = %f blue = %f alpha = %f\n', mdr, mdg, mdb, mda);

% If there is a difference, show plotted difference if requested:
if (mdr>0 || mdg>0 || mdb>0 || mda>0) && plotdiffs
    % Differences detected!
    close all;
    if plotchannel(1), figure; imagesc(diffred); title('Difference map - Channel 1 (Red):'); end
    if plotchannel(2), figure; imagesc(diffgreen); title('Difference map - Channel 2 (Green):'); end
    if plotchannel(3), figure; imagesc(diffblue);title('Difference map - Channel 3 (Blue):'); end
    if plotchannel(4), figure; imagesc(diffalpha);title('Difference map - Channel 4 (Alpha):'); end
end

if (mdr>0 || mdg>0 || mdb>0 || mda>0) || (plotdiffs > 1)
    % Now compute a more meaningful difference: The difference between the
    % stimulus as the Bits++ box would see it (i.e. how much do the 16 bit
    % intensity values of each color channel differ?):
    c=1;
    convImage = double(convImage);
    packedImage = double(theRefImage);

    switch (whichDriver)
        case {'GenericLUT'}
            % Test of generic LUT conversion:
            deconvImage = zeros(size(convImage,1), size(convImage,2));
            depackImage = zeros(size(packedImage,1), size(packedImage,2));

            if isempty(driverLUT)
                % Invert conversion: Compute 16 bpc color values from high/low byte
                % pixel data:
                deconvImage(:,:) = 256 * convImage(:, :, 1) + convImage(:, :, 2);
                depackImage(:,:) = 256 * packedImage(:, :, 1) + packedImage(:, :, 2);
            else
                % Invert conversion by use of 'driverLUT':
                fprintf('Inverting user provided LUT mapping - This can take very long...\n');
                for row=1:size(convImage,1)
                    fprintf('Pass 1 of 2: Row %i of %i...\n', row, size(convImage,1));
                    for col=1:size(convImage,2)
                        candidatesa = find(lut(1, :) == convImage(row,col,1));
                        candidatesb = find(lut(2, :) == convImage(row,col,2));
                        candidatesc = find(lut(3, :) == convImage(row,col,3));
                        candidatesd = find(lut(4, :) == convImage(row,col,4));
                        candidates1 = intersect(candidatesa, candidatesb);
                        candidates2 = intersect(candidatesc, candidatesd);
                        deconvImage(row,col) = min(intersect(candidates1, candidates2) - 1);
                    end
                end

                for row=1:size(packedImage,1)
                    fprintf('Pass 2 of 2: Row %i of %i...\n', row, size(convImage,1));
                    for col=1:size(convImage,2)
                        candidatesa = find(lut(1, :) == packedImage(row,col,1));
                        candidatesb = find(lut(2, :) == packedImage(row,col,2));
                        candidatesc = find(lut(3, :) == packedImage(row,col,3));
                        candidatesd = find(lut(4, :) == packedImage(row,col,4));
                        candidates1 = intersect(candidatesa, candidatesb);
                        candidates2 = intersect(candidatesc, candidatesd);
                        depackImage(row,col) = min(intersect(candidates1, candidates2) - 1);
                    end
                end
            end

        case {'VideoSwitcherSimple'}
            % Test of simple VideoSwitcher driver:
            % This is the (kind of) real value range of the device:
            driverNSlots = 256 * driverBTRR;
            
            % Remap:
            deconvImage = ((convImage(:, :, 1) + convImage(:, :, 3) * driverBTRR) / (driverBTRR + 1)) / 255 * (driverNSlots - 1);
            depackImage = ((packedImage(:, :, 1) + packedImage(:, :, 3) * driverBTRR) / (driverBTRR + 1)) / 255 * (driverNSlots - 1);
            
            figure;
            hiconvImage = convImage(:,:,3);
            loconvImage = convImage(:,:,1);
            higpu = hiconvImage(:);
            lowgpu = loconvImage(:);
            lumi = theInImage(:);
            j = 1:length(higpu);
            plot(lumi, higpu, '-', lumi, lowgpu, '--');
            legend('High-Byte', 'Low-Byte');
            title('GPU results in raw bytes: (x=Normalized Luminance (Req.) No., y = Byte value)');

        case {'VideoSwitcherCalibrated'}
            % Test of LUT calibrated VideoSwitcher driver:
            % This is the (kind of) real value range of the device:
            driverNSlots = 256 * driverBTRR;
            
            % Remap:
            deconvImage = ((convImage(:, :, 1) + convImage(:, :, 3) * driverBTRR) / (driverBTRR + 1)) / 255 * (driverNSlots - 1);
            depackImage = ((packedImage(:, :, 1) + packedImage(:, :, 3) * driverBTRR) / (driverBTRR + 1)) / 255 * (driverNSlots - 1);
            
            figure;
            hiconvImage = convImage(:,:,3);
            loconvImage = convImage(:,:,1);
            higpu = hiconvImage(:);
            lowgpu = loconvImage(:);
            lumi = theInImage(:);
            j = 1:length(higpu);
            plot(lumi, higpu, '-', lumi, lowgpu, '--');
            legend('High-Byte', 'Low-Byte');
            title('GPU results in raw bytes: (x=Normalized Luminance (Req.) No., y = Byte value)');
            
            % Compute average iteration count in shader etc.:
            meaniterations = mean(mean(convImage(:,:,4)));
            miniterations = min(min(convImage(:,:,4)));
            maxiterations = max(max(convImage(:,:,4)));
            fprintf('Per-Pixel search iterations in conversion shader: Min = %i, Max = %i, Mean = %f.\n', miniterations, maxiterations, meaniterations);
            
        otherwise
            error('Switch statement in deconversion part does not recognize driver name! Implementation bug!?!');
    end
    
    % Difference image:
    diffImage = (deconvImage - depackImage);

    % Find locations where pixels differ:
    idxdiff = find(abs(diffImage) > 0);
    numdiff(c) = length(idxdiff);
    numtot(c) = size(diffImage,1)*size(diffImage,2);
    maxdiff(c) = max(max(abs(diffImage)));
    
    if plotdiffs > 1
        idxdiff = find(diffImage~=inf);
    end
    
    [row col] = ind2sub(size(diffImage), idxdiff);

    % Print out all pixels values which differ, and their difference:
    if plotdiffs
        figure;
        dgpu = deconvImage(:);
        dcpu = depackImage(:);
        lumi = theInImage(:);
        j = 1:length(dgpu);
        plot(lumi, dgpu, '-', lumi, dcpu, '--');
        legend('GPU', 'Matlab/Octave');
        title('GPU vs. CPU results in device units: (x=Normalized Luminance (Req.) No., y = Luminance units)');

        for j=1:length(row)
            fprintf('Diff: %.2f Requested: %.10f  Actual: GPU %f vs. CPU %f\n', diffImage(row(j), col(j)), theInImage(row(j), col(j)) * (driverNSlots-1), deconvImage(row(j), col(j)), depackImage(row(j), col(j)));
        end
    end

    totalmaxdiff = max(maxdiff);
    
    % Summarize for this color channel:
    fprintf('\n\nIn remapped image: %i out of %i pixels differ. The maximum absolute difference is %f device units.\nTotal difference range: [%f  -  %f]\n', numdiff(c), numtot(c), maxdiff(c), min(min(diffImage)), max(max(diffImage)));
    fprintf('The maximum absolute difference corresponds to %f %% of the total operating range of the device.\n', maxdiff(c) / (driverNSlots-1) * 100);
    fprintf('Displayed differences and values are in "device units". They are proportional to levels of luminance (by an unknown factor)');
else
    % No difference in raw values implies no difference at all:
    totalmaxdiff = 0;
end

if (mdr>0 || mdg>0 || mdb>0 || mda>0) && (totalmaxdiff > 1.1) && ~forcesuccess
    fprintf('\n\n');
    fprintf('------------------ SIGNIFICANT DIFFERENCE IN CONVERSION DETECTED -----------------------\n');
    fprintf('The difference is %f, ie., it is more than 1 device unit.\n', totalmaxdiff);
    fprintf('This should not happen on properly and accurately working graphics hardware.\n');
    fprintf('Either there is a bug in the graphics driver, or something is misconfigured or\n');
    fprintf('your hardware is too old and not capable of performing the calculations in sufficient\n');
    fprintf('precision.\nYou may want to check your configuration and upgrade your driver. If that\n');
    fprintf('does not help, upgrade your graphics hardware. Alternatively you may want to use the old\n');
    fprintf('Matlab-based conversion function for slow conversion of images.\n\n');
    fprintf('Please report this failure with a description of your hardware setup to the Psychtoolbox\n');
    fprintf('forum (http://psychtoolbox.org --> Link to the forum.)\n\n');
    fprintf('You can force this test to succeed if you set the optional "forcesuccess" flag for this\n');
    fprintf('script to one and rerun it.\n\n');

    Screen('Preference', 'Verbosity', oldverbosity);
    Screen('Preference', 'SkipSyncTests', oldsynclevel);

    error('Conversion test failed. Results of Matlab code and GPU conversion differ!');
end

if (mdr>0 || mdg>0 || mdb>0 || mda>0) && (totalmaxdiff <= 1.1)
    fprintf('\n\n');
    fprintf('------------------ SMALL, PROBABLY INSIGNIFICANT DIFFERENCE IN CONVERSION DETECTED -----\n');
    fprintf('The difference is %f, ie., it is only 1 device unit or less.\n', totalmaxdiff);
    fprintf('Such a small deviation between Matlab''s/Octave''s result and the GPU result is usually \n');
    fprintf('within the tolerable range of deviations. It is likely an artifact of the test procedure\n');
    fprintf('itself or smallish numeric precision error on either GPU or CPU. Anyway, this minimal   \n');
    fprintf('difference will likely introduce an error that is much smaller than the error introduced\n');
    fprintf('by drift and tolerances of your converter and display device, and errors in calibration.\n');
    fprintf('You should inspect the numeric output above, and the plots and stimuli, but likely you  \n');
    fprintf('do not need to worry about this off-by-one difference.\n\n');

end

if (mdr==0 && mdg==0 && mdb==0 && mda==0)
    fprintf('\n\n');
    fprintf('------------------ PERFECT CONVERSION DETECTED -------------------------------\n');
    fprintf('The difference is zero - All implementations deliver exactly the same results.\n');
end

fprintf('\n\n------------------- Conversion test success! -------------------------------------\n\n');
fprintf('Imaging pipeline conversion verified to work correctly. Validation info stored.\n');

% Done for now.
return;
