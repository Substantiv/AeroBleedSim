%% ========================================================================
% 环控负载模拟系统辨识主程序 (v9.1 时间窗截取版)
% 包含：1. 静态辨识：使用鲁棒回归提取 K 值 (稳态数据不滤波)
%       2. 动态辨识：基于阻塞流公式修正，支持指定时间窗口 (500s-1500s)
%       3. 参数导出：自动计算 Simulink 所需参数
% ========================================================================
clear; clc; close all;

%% 0. 全局绘图风格设置
set(0, 'DefaultAxesFontName', 'Times New Roman');
set(0, 'DefaultTextFontName', 'Times New Roman');
set(0, 'DefaultAxesFontSize', 12);
set(0, 'DefaultLineLineWidth', 1.5);

%% 1. 参数设置与物理常数
GlobalParams.R = 287;            % 气体常数 J/(kg*K)
GlobalParams.Patm = 101.325;     % 标准大气压 (kPa)
GlobalParams.DeadZone = 0;       % 阀门死区
GlobalParams.Filter_Cutoff = 10; % 动态数据滤波截止频率 (Hz)

% [时间窗口设置] 仅使用此范围内的数据进行动态辨识
GlobalParams.StartTime = 500;    % 开始时间 (秒) 500
GlobalParams.EndTime   = 1500;   % 结束时间 (秒) 1500

% [标称工况]
GlobalParams.P_ref = 400;        % 标称阀前压力 (kPa)
GlobalParams.T_ref = 30;         % 标称管路温度 (degC)

% 颜色定义
GlobalParams.Color_Meas = [0, 0.4470, 0.7410];
GlobalParams.Color_Fit  = [0.8500, 0.3250, 0.0980];
GlobalParams.Color_Ref  = [0.4660, 0.6740, 0.1880];

%% 2. 加载数据
% --- 加载稳态数据 (保持原始，不进行滤波) ---
try
    steady_path = './data/Q31Q32_Steady.mat';
    steady_struct = load(steady_path);
    flds = fieldnames(steady_struct);
    steady_data = steady_struct.(flds{1});
catch
    warning('未找到稳态数据文件，生成模拟数据用于演示...');
    steady_data = table((0:10:100)', (0:10:100)'*0.5, 'VariableNames', {'X31','Q31'});
    steady_data.X32 = steady_data.X31; steady_data.Q32 = steady_data.Q31 * 0.98;
end

% --- 加载动态数据 ---
try
    dyn_path = './data/Q31Q32_400MPa_Dynamic.mat';
    dyn_struct = load(dyn_path);
    flds = fieldnames(dyn_struct);
    dyn_data = dyn_struct.(flds{1});
catch
    warning('未找到动态数据文件，生成模拟数据用于演示...');
    % 生成足够长的时间覆盖 500-1500s，以便演示代码不报错
    t = (0:0.1:1600)'; 
    dyn_data = table(t, 'VariableNames', {'Time'});
    dyn_data.P30 = 400 + randn(size(t)); dyn_data.T30 = 30*ones(size(t));
    % 在 500-1500s 区域加一些特定的正弦激励
    dyn_data.X31 = 50 + 40*sin(t*0.1); 
    dyn_data.Q31 = 0.5*dyn_data.X31;
    dyn_data.X32 = dyn_data.X31; dyn_data.Q32 = 0.49*dyn_data.X32;
end

% --- 动态数据预处理 (NaN填充 -> 滤波 -> 时间截取) ---
if ~isempty(dyn_data)
    % 1. 填充 NaN
    vars = dyn_data.Properties.VariableNames;
    for i = 1:length(vars)
        if any(isnan(dyn_data.(vars{i})))
            dyn_data.(vars{i}) = fillmissing(dyn_data.(vars{i}), 'linear');
        end
    end
    
    % 2. 零相位滤波 (先对全量数据滤波，避免截取后的边界效应)
    Time_vec_full = dyn_data.Time;
    dt = mean(diff(Time_vec_full));
    Fs = 1/dt; 
    
    if exist('filtfilt', 'file')
        d = designfilt('lowpassiir', 'FilterOrder', 2, ...
            'HalfPowerFrequency', GlobalParams.Filter_Cutoff, 'SampleRate', Fs);
            
        fprintf('正在应用零相位滤波 (%.1f Hz)...\n', GlobalParams.Filter_Cutoff);
        filter_targets = {'Q31', 'Q32', 'X31', 'X32', 'P30', 'T30'};
        
        for i = 1:length(filter_targets)
            var_name = filter_targets{i};
            if ismember(var_name, dyn_data.Properties.VariableNames)
                dyn_data.(var_name) = filtfilt(d, dyn_data.(var_name));
            end
        end
    end
    
    % 3. [关键步骤] 时间截取 (Slicing)
    fprintf('正在截取数据片段: %.1fs 到 %.1fs ...\n', GlobalParams.StartTime, GlobalParams.EndTime);
    
    % 找到对应的时间索引
    idx_window = dyn_data.Time >= GlobalParams.StartTime & dyn_data.Time <= GlobalParams.EndTime;
    
    if sum(idx_window) > 10 % 确保至少有数据
        dyn_data = dyn_data(idx_window, :);
        % 重置时间轴从0开始? 通常辨识不需要重置，保持绝对时间即可
        % 如果需要重置: dyn_data.Time = dyn_data.Time - dyn_data.Time(1);
        fprintf('  -> 截取成功，剩余数据点数: %d\n', height(dyn_data));
    else
        warning('指定的时间范围内(%.1fs-%.1fs)没有足够的数据！将使用全部数据继续。', ...
            GlobalParams.StartTime, GlobalParams.EndTime);
    end
end

%% 3. 执行辨识
fprintf('\n>>> 开始辨识 Channel 31 (空调路)...\n');
Result31 = identify_branch(steady_data, dyn_data, '31', GlobalParams);

fprintf('\n>>> 开始辨识 Channel 32 (防冰路)...\n');
Result32 = identify_branch(steady_data, dyn_data, '32', GlobalParams);

%% 4. 输出最终报告
fprintf('\n======================================================\n');
fprintf('           SYSTEM IDENTIFICATION REPORT               \n');
fprintf('======================================================\n');
fprintf('Time Range: %.1fs - %.1fs\n', GlobalParams.StartTime, GlobalParams.EndTime);
fprintf('Channel 31: K=%.4f, Tp=%.4f, Tau=%.4f\n', Result31.K_slope, Result31.Tp, Result31.Tau);
fprintf('Channel 32: K=%.4f, Tp=%.4f, Tau=%.4f\n', Result32.K_slope, Result32.Tp, Result32.Tau);
fprintf('======================================================\n');

%% 5. 导出到工作区
K31 = Result31.K_slope; Tp31 = Result31.Tp; Tau31 = Result31.Tau;
K32 = Result32.K_slope; Tp32 = Result32.Tp; Tau32 = Result32.Tau;

% 流量计的测量时滞设置
Tau31 = 5; Tau32 = 5;

% --- 物理常数与标称工况 ---
P_ref = GlobalParams.P_ref;
T_ref = GlobalParams.T_ref;
R_gas = GlobalParams.R;
Patm  = GlobalParams.Patm;

%% ========================================================================
%  核心辨识函数
% ========================================================================
function Result = identify_branch(steady_data, dyn_data, ch_suffix, P)
    X_name = ['X' ch_suffix];
    Q_name = ['Q' ch_suffix];
    
    % --- Step 1: 静态参数辨识 (Robust Regression) ---
    X_s = steady_data.(X_name);
    Q_s = steady_data.(Q_name);
    
    try
        b = robustfit(X_s, Q_s, 'bisquare', 4.685, 'off');
        K_slope = b(1);
    catch
        K_slope = X_s \ Q_s; 
    end
    
    % 计算标称参考因子
    T_ref_K = P.T_ref + 273.15;
    Term_Ref = P.P_ref / sqrt(T_ref_K);
    
    % 绘图 - 静态
    figure('Name', ['Static ID ' ch_suffix], 'Color', 'w', 'Position', [100, 100, 500, 300]);
    scatter(X_s, Q_s, 30, 'k', 'filled', 'MarkerFaceAlpha', 0.3); hold on;
    plot(linspace(0,100,100), K_slope*linspace(0,100,100), 'r-', 'LineWidth', 2);
    title(['Static Fit Ch' ch_suffix ' (K=' num2str(K_slope, '%.4f') ')']);
    xlabel('Valve Opening (%)'); ylabel('Flow'); grid on;

    % --- Step 2: 动态特性辨识 ---
    Time = dyn_data.Time;
    Ts = mean(diff(Time));
    X_d = dyn_data.(X_name);
    Q_d = dyn_data.(Q_name);
    
    % 1. 计算动态物理因子 (阻塞流)
    P_dyn = dyn_data.P30;
    T_dyn = dyn_data.T30 + 273.15;
    Term_Dyn = P_dyn ./ sqrt(T_dyn);
    
    % 2. 计算物理修正比率
    Physics_Ratio = Term_Dyn / Term_Ref;
    
    % 3. 归一化输出
    Q_norm = Q_d ./ Physics_Ratio;
    
    % 4. 辨识传递函数: X -> Q_norm
    data_id = iddata(Q_norm, X_d, Ts);
    opt = procestOptions; opt.Display = 'off';
    
    try
        model = procest(data_id, 'P1D', opt);
    catch
        model = procest(data_id, 'P1', opt);
    end
    
    % --- Step 3: 验证 ---
    % 注意：验证时也要基于截取后的 Time 轴进行仿真
    Q_sim_norm = lsim(tf(model), X_d, Time);
    Q_sim_final = Q_sim_norm .* Physics_Ratio;
    
    fit_val = 100 * (1 - norm(Q_d - Q_sim_final)/norm(Q_d - mean(Q_d)));

    % 绘图 - 动态
    figure('Name', ['Dynamic ID ' ch_suffix], 'Color', 'w', 'Position', [600, 100, 600, 400]);
    plot(Time, Q_d, 'b-', 'LineWidth', 1); hold on;
    plot(Time, Q_sim_final, 'r--', 'LineWidth', 1.5);
    % 在标题中显示时间范围，方便确认
    title({['Dynamic Ch' ch_suffix ' (Fit: ' num2str(fit_val,'%.2f') '%)']; 
           ['Time Window: ' num2str(Time(1),'%.0f') 's - ' num2str(Time(end),'%.0f') 's']});
    legend('Measured', 'Simulated Model');
    xlabel('Time (s)'); grid on;
    
    Result.K_slope = K_slope;
    Result.Tp = model.Tp1;
    Result.Tau = model.Td;
end