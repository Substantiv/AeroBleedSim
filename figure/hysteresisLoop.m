clc; clear; close all;

myFont = 'Microsoft YaHei'; 

% === 1. 参数设置 ===
Start_Deadband = 2.0; % 启动阈值 (红线)
Stop_Deadband  = 0.5; % 停止阈值 (绿线)

% === 2. 生成数据 ===
% 模拟两段过程：
% Phase 1: 误差从 0 慢慢增加到 3.5 (去程)
err_up = 0 : 0.01 : 3.5;
% Phase 2: 误差从 3.5 慢慢减小到 0 (回程)
err_down = 3.5 : -0.01 : 0;

% 合并数据输入
error_input = [err_up, err_down];

% 初始化状态变量
isAdjusting = false;
state_output = zeros(size(error_input));

% === 3. 运行逻辑 ===
for i = 1:length(error_input)
    err = error_input(i);
    
    if isAdjusting
        % 状态：运动中
        if err <= Stop_Deadband
            isAdjusting = false; % 停止
        else
            isAdjusting = true;  % 继续动
        end
    else
        % 状态：静止中
        if err > Start_Deadband
            isAdjusting = true;  % 启动
        else
            isAdjusting = false; % 保持静止
        end
    end
    state_output(i) = isAdjusting;
end

% === 4. 拆分数据以便绘图 ===
len_up = length(err_up);
state_up = state_output(1:len_up);
state_down = state_output(len_up+1:end);

% === 5. 开始绘图 ===
figure('Color', 'w');
hold on; grid on;

% 设置坐标轴默认字体，解决刻度标签乱码
set(gca, 'FontName', myFont);

% (1) 画去程 (蓝色)
plot(err_up, state_up, 'b-', 'LineWidth', 2, 'DisplayName', '误差变大过程');

% (2) 画回程 (红色虚线)
plot(err_down, state_down, 'r--', 'LineWidth', 2, 'DisplayName', '误差变小过程');

% (3) 画阈值辅助线 (注意 Label 也要设置字体)
xline(Start_Deadband, 'k:', 'LineWidth', 1.5, 'Label', '启动阈值', ...
    'LabelVerticalAlignment','bottom', 'FontName', myFont);
xline(Stop_Deadband, 'k:', 'LineWidth', 1.5, 'Label', '停止阈值', ...
    'LabelVerticalAlignment','bottom', 'FontName', myFont);

% (4) 添加箭头 (无文字，无需字体设置)
quiver(1.0, 0, 0.5, 0, 'b', 'LineWidth', 1.5, 'MaxHeadSize', 0.5, 'HandleVisibility','off');
quiver(2.5, 1, -0.5, 0, 'r', 'LineWidth', 1.5, 'MaxHeadSize', 0.5, 'HandleVisibility','off');

% === 6. 图表美化 (关键：所有带中文的地方都要加 FontName) ===
title('迟滞环逻辑图', 'FontName', myFont, 'FontSize', 14);
xlabel('误差绝对值 (Error)', 'FontName', myFont, 'FontSize', 12);
ylabel('系统状态 (0=静止, 1=运动)', 'FontName', myFont, 'FontSize', 12);
ylim([-0.2, 1.2]);

% 图例
legend('Location', 'best', 'FontName', myFont);

% 设置Y轴刻度标签
yticks([0 1]);
yticklabels({'OFF (静止)', 'ON (调节)'});

% 填充迟滞区间
fill([0.5 2.0 2.0 0.5], [0 0 1 1], [0.9 0.9 0.9], ...
    'FaceAlpha', 0.5, 'EdgeColor', 'none', 'DisplayName', '迟滞区间');

% 调整图层顺序
children = get(gca, 'children');
set(gca, 'children', flipud(children));

hold off;