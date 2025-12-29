clc; clear; close all;

%% ========================== 1. 阀门辨识 ==========================
% 执行阀门系统辨识，并暂存关键参数（避免后续脚本清空变量）
run('sys_id_value.m');
save('temp_id.mat', 'X31_num', 'X31_den', 'X32_num', 'X32_den');

%% ========================== 2. 管路辨识 ==========================
% 注意：sys_id_pipeline.m 会清空工作区，因此需在之后恢复阀门数据
run('sys_id_pipeline.m');

%% ========================== 3. 恢复变量并整理环境 ==========================
load('temp_id.mat'); 
delete('temp_id.mat');

% 清除非核心变量，保留 Simulink 运行所需的全部参数
clearvars -except ...
    X31_num X31_den X32_num X32_den ...       % 阀门辨识结果
    K31 Tp31 Tau31 K32 Tp32 Tau32 ...         % 管路辨识结果
    P_ref T_ref R_gas Patm;                   % 物理常数

%% ========================== 4. 管路参数设置 ==========================
% 公共管路：长度 5 m，直径 DN100 (0.1 m)
% V = pi*r^2*L
V_vol = pi * (0.05)^2 * 5;

% 气源模式设置
%   1 = 动态任务剖面 (Dynamic Mission Profile)
%   2 = 静态设计点 (Static Design Point)
%   3 = 静态设计点 + 正弦波动 (Static + Sine Wave)
AirSourceMode = 2;

Knoise = 0;
dt = 0.01;

%% ========================== 5. 控制器选择和参数配置 ==========================
% PID 控制器
% L1AC 自适应控制器
% ASMC 滑模控制器
EBASctrlMode = 'l1ac';

% PID 控制器
% Smith PI 控制器
% Smith PI 控制器
% Smith 增广状态积分型iLQR 控制器
ECSctrlMode = 'pid';

if strcmp(EBASctrlMode, 'l1ac')
    % 定义 L1 参数结构体 (使用局部变量 P_L1_Struct)
    P_L1_Struct = struct();
    P_L1_Struct.Ts = 0.01; % 采样时间
    
    % [1] 压力环 (PRSOV) 参数
    % 特点: 响应极快，系统增益 Bm 为正 (开阀->增压)
    P_L1_Struct.Press.Am    = 10;     % 参考模型带宽 (rad/s)
    P_L1_Struct.Press.Gamma = 1000;   % 自适应增益
    P_L1_Struct.Press.Bm    = 200;    % 标称输入增益 (估计值)
    P_L1_Struct.Press.Wc    = 30;     % 低通滤波器截止频率 (rad/s)
    
    % [2] 温度环 (FAV) 参数
    % 特点: 有热惯性响应较慢，系统增益 Bm 为负 (开阀->降温)
    P_L1_Struct.Temp.Am    = 2;       % 参考模型带宽
    P_L1_Struct.Temp.Gamma = 500;     % 自适应增益
    P_L1_Struct.Temp.Bm    = -50;     % [注意] 负增益
    P_L1_Struct.Temp.Wc    = 10;      % 滤波器截止频率
    
    % 导出到工作区，变量名为 P_L1
    assignin('base', 'P_L1', P_L1_Struct);
    
    fprintf('>>> EBAS (L1) 参数已设置完成 (变量名: P_L1)。\n');
    fprintf('    压力环: Am=%.1f, Gamma=%.1f, Bm=%.1f, Wc=%.1f\n', ...
        P_L1_Struct.Press.Am, P_L1_Struct.Press.Gamma, P_L1_Struct.Press.Bm, P_L1_Struct.Press.Wc);
    fprintf('    温度环: Am=%.1f, Gamma=%.1f, Bm=%.1f, Wc=%.1f\n', ...
        P_L1_Struct.Temp.Am, P_L1_Struct.Temp.Gamma, P_L1_Struct.Temp.Bm, P_L1_Struct.Temp.Wc);
end

fprintf('>>> 系统参数加载完成\n');

%% ========================== 6. 启动 Simulink 模型 ==========================
open_system('AirManagementSystem.slx');
disp('>>> Simulink 模型已打开，请开始仿真。');
