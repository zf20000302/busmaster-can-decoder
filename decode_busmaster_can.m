% ================================================================
% BUSMASTER CAN Log Decoder (MATLAB)
%
% Author : Chih-Feng Huang (Vincent Huang)
% Email : zf20000302@gmail.com
% GitHub : https://github.com/zf20000302
%
% Version : v1.0
% Last Updated : 2026-03
%
% Description:
%   Decode BUSMASTER CAN log files using DBC definitions and export
%   each decoded signal as a MATLAB timetable.
%
% Inputs:
%   logFile - path to CAN log file
%   dbcFile - path to DBC file
%
% Outputs:
%   One timetable per decoded signal in the MATLAB base workspace.
%
% Notes:
%   - This script is intended for interactive MATLAB workflow.
%   - Decoded signal timetables are exported directly to the base workspace.
%   - BUSMASTER log Numeric Format must be set to Decimal.
%   - This script assumes the CAN ID and payload bytes in the log file are recorded in decimal format.
%   - Supports Intel (@1) and Motorola (@0) signal decoding.
%   - Time format in log is assumed to be hh:mm:ss:ffff.
%   - Motorola decoding follows standard DBC bit numbering convention.
%   - Standard CAN IDs (11-bit) are supported.
%   - Extended CAN IDs (29-bit) have not been fully validated.
% ================================================================

clc;clar;close all;
% ------------------------------------------ Parse Busmaster Log ----------------------------------
logFile = "CAN_Test_260311.log";
dbcFile = "CAN_BusMasterVer2.dbc";

fid = fopen(logFile, 'r');
c = textscan(fid, '%s', 'Delimiter', '\n', 'Whitespace', '');
fclose(fid);
lines = string(c{1});
isData = ~startsWith(strtrim(lines),"***") & strlength(strtrim(lines)) >0;
dataLines = lines(isData);

n = numel(dataLines);
TimeStr = strings(n,1);
ID = zeros(n,1);
DLC = zeros(n,1);
Data = zeros(n,8,'uint8');

for i = 1:n
    tok = split( strtrim( dataLines(i) ) );
    % format:
    % 1 : Time 2:Tx/Rx 3:Channel 4:CAN ID 5:Type 6:DLC 7~14:Data
    % Matters : 1、Time, 4、CAN ID, 7~14、Data
    TimeStr(i) = tok(1);
    ID(i) = str2double(tok(4));
    
    DLC(i) = str2double(tok(6));
    
    for k = 1:min(DLC(i),8)
        Data(i,k) = uint8(str2double(tok(6+k)));
    end
end

rawTable = table(TimeStr, ID, DLC, Data);

% --- timeStr to Sec ---
n = height(rawTable);
TimeSec = zeros(n,1);

for i = 1:n
    t = char(rawTable.TimeStr(i));  % 轉成 char array
    parts = sscanf(t, '%d:%d:%d:%d');
    hh = parts(1);
    mm = parts(2);
    ss = parts(3);
    frac = parts(4);   
    
    % 14:10:07:7349
    TimeSec(i) = hh*3600 + mm*60 + ss + frac/10000;
end

t0 = TimeSec(1);
TimeSec = TimeSec - t0;

rawTable.TimeStr = [];
rawTable.Time = TimeSec;  
rawTable = movevars(rawTable, 'Time', 'Before', 'ID');

% ------------------------------------------- Parse  dbc file ------------------------------------------

dbcTxt=fileread(dbcFile);
dbcLines = splitlines(string(dbcTxt));

msgInfo = struct();
msgOrder = strings(0);
currentMsg = "";

for i  = 1 : numel(dbcLines)
    line = strtrim(dbcLines(i));
    
    %take out msg line, not signal line
    %BO_ 632 RxPD0: 8 Vector__XXX
    % |        |       |           └── (\d+)                → DLC 
    % |        |      └───────── (\w+)          → Message Name 
    % |       └───────────── (\d+)        → ID 
    %└────────────────── ^BO_    
    tokMsg = regexp(line, '^BO_\s+(\d+)\s+(\w+)\s*:\s*(\d+)', 'tokens', 'once' );
    
    if ~isempty(tokMsg)
        msgID = str2double(tokMsg{1});
        msgName = string(tokMsg{2});
        msgDLC = str2double(tokMsg{3});
        
        currentMsg = msgName;
        msgOrder(end+1) = msgName;
    
        % Dynamic Field Name : field name 不是固定，而是變數 => msgName
        msgInfo.(msgName) = struct( ...
            'ID', msgID, ...
            'DLC', msgDLC, ...
            'Signals', [] );
        continue;
    end
    
    % SG_ SC_fb_BatSOC : 0|8@1+ (1,0) [0|255] "%" Vector__XXX
    %           |                          |  |     |  |     |          |          └── "([^"]*)"                                     → Unit
    %           |                          |  |     |  |     |         └──────── \[([^\]]*)\]                              → Range
    %           |                          |  |     |  |    └─────────────── \(([^\)]*)\)                      → Factor, Offset
    %           |                          |  |     | └────────────────── ([+-])                             → Sign (+ unsigned, - signed)
    %           |                          |  |    └──────────────────── ([01])                          → Byte Order (1 Intel, 0 Motorola)
    %           |                          | └────────────────────── (\d+)                           → Signal Length
    %           |                         └──────────────────────────────── (\d+)   → Start Bit
    %          └──────────────────────────────────────── (\w+)        → Signal Name
    % └───────────────────────────────────────── ^SG_
    tokSig = regexp(line, ...
       '^SG_\s+(\w+)\s*:\s*(\d+)\|(\d+)@([01])([+-])\s*\(([^\)]*)\)\s*\[([^\]]*)\]\s*"([^"]*)"', ...
        'tokens','once');
    
    if ~isempty(tokSig)  && currentMsg ~= ""
        sigName = string(tokSig{1});
        startBit = str2double(tokSig{2});
        sigLen = str2double(tokSig{3});
        byteOrder = str2double(tokSig{4});  % 1 = Intel, 0 = Motorola
        signChar = string(tokSig{5});               % + / -
        factorOff = split(string(tokSig{6}),",");
        factor = str2double(strtrim(factorOff(1)));
        offset = str2double(strtrim(factorOff(2)));
        unitStr = string(tokSig{8});
        sigStruct = struct( ...
            'Name',sigName, ...
            'StartBit', startBit, ...
            'Length', sigLen, ...
            'ByteOrder', byteOrder, ...
            'Signed', signChar == "-", ...
            'Factor', factor, ...
            'Offset', offset, ...
            'Unit', unitStr);
    
        if isempty(msgInfo.(currentMsg).Signals)
            msgInfo.(currentMsg).Signals = sigStruct;
        else
            msgInfo.(currentMsg).Signals(end+1) = sigStruct;
        end
    end
end

% --- Build ID -> MessageName Map ---
% BO_ 632 RxPD0: 8 Vector__XXX  -> 632, RxPD0

idMap = containers.Map('KeyType','double','ValueType','char');

for i = 1:numel(msgOrder)
    msgName = msgOrder(i);
    idMap(msgInfo.(msgName).ID) = char(msgName);
end

% --------------------------------------------- extract Signal Raw ---------------------------------------------
signals = struct();

for i = 1:height(rawTable)
    frameID = rawTable.ID(i);   % raw Data
    
    if ~isKey(idMap, frameID)
        continue;
    end
    
    msgName = string(idMap(frameID));  
    sigDefs = msgInfo.(msgName).Signals;
    dataBytes = rawTable.Data(i,:);    %uint8 1x8
    t = rawTable.Time(i);
    
    for k = 1:numel(sigDefs)
        sig = sigDefs(k);
        
        rawVal = extractSignalRaw(dataBytes, sig.StartBit, sig.Length, sig.ByteOrder, sig.Signed);
        phyVal = double(rawVal) * sig.Factor + sig.Offset;
        
        sigName = char(sig.Name);
        
        if ~isfield(signals, sigName)
            signals.(sigName).Time = [];
            signals.(sigName).Value = [];
            signals.(sigName).Unit = char(sig.Unit);
            signals.(sigName).Message = char(msgName);
            signals.(sigName).ID = frameID;
        end
        
        signals.(sigName).Time(end+1,1) = t;
        signals.(sigName).Value(end+1,1) = phyVal;
    end
end


% ------------------------------------------------ Export each Signal to timetable ------------------------------------------------
sigList = fieldnames(signals);

for i = 1:numel(sigList)
    sigName = sigList{i};
    
    TT = timetable( ...
        seconds(signals.(sigName).Time), ...
        signals.(sigName).Value, ...
        'VariableNames',{sigName});
    signals.(sigName).TT = TT;
    
    assignin('base',sigName,TT);
    
end

vars = whos;
for i = 1:length(vars)
    if ~strcmp(vars(i).class,'timetable')
        clear(vars(i).name)
    end
end
clear i vars TT;

% ------------------------------------------------ Local Functions ------------------------------------------------
function rawVal = extractSignalRaw(dataBytes, startBit, sigLen, byteOrder, isSigned)
    % dataBytes : 1x8 uint8
    % byteOrder : 1 = Intel(little-endian), 0 = Motorola(big-endian)
    
    dataBytes = uint8(dataBytes);
    
    if byteOrder == 1
        % Intel : bit0 = byte 1 LSB
        % byte1 byte2 byte3 ...
        % LSB -> MSB
        rawUnsigned = uint64(0);
        
        for b = 1:8
            % byte1 + byte2 << 8 + byte3 <<16 + byte4 << 24
            rawUnsigned = rawUnsigned + bitshift(uint64(dataBytes(b)),8*(b-1));
        end
        
        % sigLen = 8 , 1<< 8 = 256, 256-1 = 255 -> bin : 0000000011111111
        mask = bitshift(uint64(1), sigLen) -1;
        % 0b1100101010110010, startBit = 4, shift -4 -> 0b0000110010101011
        % (payload >> startBit) & mask
        rawUnsigned = bitand(bitshift(rawUnsigned, -startBit), mask);
    else
        % Motorola : 
        bitVec = zeros(1,64);
        idx = 1;
        for byteIdx = 1:8
            thisByte = dataBytes(byteIdx);
            bits = bitget(thisByte, 8:-1:1);    % MSB -> LSB
            bitVec(idx:idx+7) = bits;
            idx = idx + 8;
        end
        dbc2vec = @(sb) floor(sb/8)*8 + (8-mod(sb,8));
        startIdx = dbc2vec(startBit);
        
        rawUnsigned = uint64(0);
        for m = 0:sigLen-1
            rawUnsigned = bitshift(rawUnsigned,1) + uint64(bitVec(startIdx+m));
        end
    end

    if isSigned
        signBit = bitshift(uint64(1),sigLen-1);
        fullScale = bitshift(uint64(1),sigLen);
        if bitand(rawUnsigned, signBit) ~= 0
            rawVal = int64(rawUnsigned) - int64(fullScale);
        else
            rawVal = int64(rawUnsigned);
        end
    else
        rawVal = double(rawUnsigned);
    end
end