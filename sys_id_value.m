clc; clear;

%% === 第一步：加载数据 (Step 1: Load Data) ===
if exist('./data/X31X32ValueSysID.mat', 'file')
    load('./data/X31X32ValueSysID.mat');
else
    % 如果没有数据，生成模拟含噪数据用于演示 (仅供测试)
    fprintf('警告: 未找到数据文件，正在生成模拟含噪数据用于演示...\n');
    data.Time = (0:0.001:10)';
    data.X31Cmd = idinput(length(data.Time), 'rbs');
    sys_true = tf(100, [1, 14, 100], 'InputDelay', 0.02);
    data.X31Real = lsim(sys_true, data.X31Cmd, data.Time) + 0.1*randn(size(data.Time)); % 加噪声
    data.X32Cmd = data.X31Cmd; data.X32Real = data.X31Real;
end

% 提取数据
t = data.Time;
Ts = mean(diff(t)); 
Fs = 1/Ts; % 采样频率
fprintf('系统采样时间 Ts = %.4f s (采样率 Fs = %.1f Hz)\n', Ts, Fs);

%% === 第二步：高级数据预处理 (Step 2: Pre-processing with Noise Handling) ===

% 2.1 创建原始 iddata 对象
data_X31_raw = iddata(data.X31Real, data.X31Cmd, Ts);
data_X32_raw = iddata(data.X32Real, data.X32Cmd, Ts);

data_X31_raw.TimeUnit = 'seconds'; 
data_X32_raw.TimeUnit = 'seconds';

% 2.2 零相位低通滤波 (Zero-phase Filtering)
% 策略: 过滤掉高频噪声，但保留系统动态。
% 截止频率建议: 设置为系统估计带宽的 5-10 倍，或 Nyquist 频率的 0.1-0.2 倍
FilterCutoff = 0.2; % 归一化频率 (0 到 0.5, 0.5 代表 Nyquist频率)
% 物理截止频率约为: FilterCutoff * (Fs/2) Hz

fprintf('正在执行零相位滤波 (Cutoff = %.1f Hz)...\n', FilterCutoff * (Fs/2));

% 使用 idfilt 进行滤波 (因果+非因果 = 零相位)
data_X31_filt = idfilt(data_X31_raw, [0, FilterCutoff]); 
data_X32_filt = idfilt(data_X32_raw, [0, FilterCutoff]);

% 2.3 去趋势 (Detrend)
% 对滤波后的数据进行去趋势
data_X31 = detrend(data_X31_filt);
data_X32 = detrend(data_X32_filt);

% 2.4 划分数据集
split_idx = floor(length(t) / 2);

est_X31 = data_X31(1:split_idx);
val_X31 = data_X31(split_idx+1:end);

est_X32 = data_X32(1:split_idx);
val_X32 = data_X32(split_idx+1:end);

%% === 第三步：鲁棒模型辨识 - X31 (Step 3: Robust Identification) ===
fprintf('\n========================================\n');
fprintf('正在辨识 X31 ...\n');
fprintf('========================================\n');

%  配置抗噪辨识选项
opt = tfestOptions('Display', 'off');
opt.SearchMethod = 'lsqnonlin'; % 使用非线性最小二乘法，比默认的 'auto' 更稳健

% 延迟时间处理
% 用 delayest 估算延迟 (返回值为采样点数)
nk_X31 = delayest(est_X31);
delay_time_X31 = nk_X31 * Ts;
fprintf('自动估算 X31 延迟: %d 个采样点 (%.4f 秒)\n', nk_X31, delay_time_X31);

% 3.1 辨识模型
% 将计算出的 delay_time 传入，或者如果不需要延迟可直接设为 0
sys_X31 = tfest(est_X31, 2, 0, opt, 'InputDelay', delay_time_X31); 

% 3.2 顶刊风格绘图
plot_paper_ready('X31', val_X31, sys_X31);

% 3.3 输出参数
print_model_params('X31', sys_X31);


%% === 第四步：鲁棒模型辨识 - X32 (Step 4: Robust Identification) ===
fprintf('\n========================================\n');
fprintf('正在辨识 X32 ...\n');
fprintf('========================================\n');

% 估算 X32 延迟
nk_X32 = delayest(est_X32);
delay_time_X32 = nk_X32 * Ts;
fprintf('自动估算 X32 延迟: %d 个采样点 (%.4f 秒)\n', nk_X32, delay_time_X32);

% 使用相同的优化配置
sys_X32 = tfest(est_X32, 2, 0, opt, 'InputDelay', delay_time_X32);

% 4.2 顶刊风格绘图
plot_paper_ready('X32', val_X32, sys_X32);

% 4.3 输出参数
print_model_params('X32', sys_X32);


%% === 第五步：参数导出至工作区 (Step 5: Export to Workspace) ===
X31_num = sys_X31.Numerator;
X31_den = sys_X31.Denominator;

X32_num = sys_X32.Numerator;
X32_den = sys_X32.Denominator;

%% === 辅助函数：打印模型参数 ===
function print_model_params(name, sys)
    fprintf('\n>>> %s 最终模型参数:\n', name);
    [wn, zeta] = damp(sys);
    dc_gain = dcgain(sys);
    
    % 获取延迟时间
    if isa(sys, 'idtf')
        delay = sys.InputDelay;
    else
        delay = 0;
    end

    fprintf('  传递函数 (Transfer Function): \n');
    sys 
    fprintf('  自然频率 (wn):    %.2f rad/s (%.2f Hz)\n', wn(1), wn(1)/(2*pi));
    fprintf('  阻尼比 (zeta):    %.4f\n', zeta(1));
    fprintf('  直流增益 (Gain):  %.4f\n', dc_gain);
    fprintf('  估算延迟 (Delay): %.4f s\n', delay);
    try
        fprintf('  拟合度 (Fit):     %.2f%%\n', sys.Report.Fit.FitPercent);
    catch
        fprintf('  拟合度 (Fit):     N/A\n');
    end
end

%% === 辅助函数：生成顶刊风格绘图 ===
function plot_paper_ready(name, val_data, sys_model)
    % 1. 准备数据
    t_val = val_data.SamplingInstants; 
    y_real = val_data.OutputData;      
    u_cmd = val_data.InputData;        
    
    % 使用相对时间进行仿真
    t_rel = t_val - t_val(1);
    [y_sim, ~] = lsim(sys_model, u_cmd, t_rel); 
    
    error_sig = y_real - y_sim;

    % 2. 创建图形窗口
    figure('Name', [name ' 顶刊风格模型验证'], 'Units', 'centimeters', 'Position', [5, 5, 16, 12], 'Color', 'w');
    
    % --- 子图 1: 全景追踪 ---
    subplot(3, 1, 1);
    plot(t_val, y_real, 'k', 'LineWidth', 1.0, 'Color', [0.6 0.6 0.6], 'DisplayName', 'Exp. Data (Filtered)'); hold on;
    plot(t_val, y_sim, 'r--', 'LineWidth', 1.5, 'DisplayName', 'Model Output');
    ylabel('Position');
    title(['(a) ' name ' Global Validation'], 'FontName', 'Times New Roman', 'FontSize', 11, 'FontWeight', 'bold');
    grid on; legend('Location', 'best', 'Box', 'off');
    xlim([min(t_val), max(t_val)]);
    set(gca, 'FontName', 'Times New Roman', 'FontSize', 10);

    % --- 子图 2: 局部放大 ---
    % 自动寻找中间段
    zoom_center = t_val(floor(length(t_val)/2)); 
    zoom_span = 100; % 缩短展示时间为100秒，看清楚细节
    t_start = zoom_center; 
    t_end = zoom_center + zoom_span;

    subplot(3, 1, 2);
    plot(t_val, y_real, 'k-', 'LineWidth', 1.5, 'Color', [0.2 0.2 0.2]); hold on;
    plot(t_val, y_sim, 'r--', 'LineWidth', 1.8);
    plot(t_val, u_cmd, 'b:', 'LineWidth', 1.0); 
    
    xlim([t_start, t_end]);
    
    % 自动Y轴
    mask = (t_val >= t_start) & (t_val <= t_end);
    if any(mask)
        y_min = min(y_real(mask)); y_max = max(y_real(mask));
        margin_y = (y_max - y_min) * 0.2;
        ylim([y_min - margin_y, y_max + margin_y]);
    end

    ylabel('Position');
    title(['(b) ' name ' Transient Zoom-in'], 'FontName', 'Times New Roman', 'FontSize', 11, 'FontWeight', 'bold');
    grid on; 
    
    % 添加拟合度
    try
        fit_percent = sys_model.Report.Fit.FitPercent;
        text(t_start + zoom_span*0.05, max(ylim) - margin_y*0.5, ...
             sprintf('Fit: %.2f%%', fit_percent), ...
            'FontName', 'Times New Roman', 'FontSize', 10, 'BackgroundColor', 'w');
    catch
    end
    set(gca, 'FontName', 'Times New Roman', 'FontSize', 10);

    % --- 子图 3: 误差 ---
    subplot(3, 1, 3);
    plot(t_val, error_sig, 'Color', [0.4 0.4 0.4], 'LineWidth', 1);
    yline(0, 'k--');
    ylabel('Error'); xlabel('Time (s)');
    title(['(c) ' name ' Residual Error'], 'FontName', 'Times New Roman', 'FontSize', 11, 'FontWeight', 'bold');
    grid on;
    xlim([min(t_val), max(t_val)]);
    set(gca, 'FontName', 'Times New Roman', 'FontSize', 10);

    linkaxes([subplot(3,1,1), subplot(3,1,3)], 'x');
end