classdef sliding_2AC < matlab.apps.AppBase

    properties (Access = public)
        UIFigure                     matlab.ui.Figure
        TabGroup                     matlab.ui.container.TabGroup
        
        RecordTab                    matlab.ui.container.Tab
        InstructionTextArea          matlab.ui.control.TextArea
        StartButton                  matlab.ui.control.Button
        SubjectNumberLabel           matlab.ui.control.Label
        SubjectNumberEditField       matlab.ui.control.EditField
        TesterLabel                  matlab.ui.control.Label
        TesterDropDown               matlab.ui.control.DropDown
        TestDateLabel                matlab.ui.control.Label
        TestDatePicker               matlab.ui.control.DatePicker
        
        TestTab                      matlab.ui.container.Tab
        sButton                      matlab.ui.control.Button
        UpButton                     matlab.ui.control.Button
        DownButton                   matlab.ui.control.Button
        LightPanel                   matlab.ui.container.Panel
        FinishSignButton             matlab.ui.control.Button
        
        ResultTab                    matlab.ui.container.Tab
        UIAxes                       matlab.ui.control.UIAxes
    end
    
    properties (Access = public)
        SECOND = 4;
        REPELEMS = 5;
        
        SN = '';
        Tester = '';
        Date = datetime;
        
        audio = 0;
        answer = [];
        elems = [5, 10, 20, 50, 100];
        record = [];
        is_noise = [];
        correct = containers.Map('KeyType','int32','ValueType','int32');
        wrong = containers.Map('KeyType','int32','ValueType','int32');
        noise = 0;
        tmark = datetime;
        light_timer = timer();
    end
       
    methods (Access = private)

        function startupFcn(app)
            app.is_noise = repelem([false], 2 * 2 * app.REPELEMS * length(app.elems));
            app.record = [app.record; {'Time' 'Press' 'Answer' 'Judge'}];
            app.correct = containers.Map([app.elems -app.elems], repelem([0], 2 * length(app.elems)));
            app.wrong = containers.Map([app.elems -app.elems], repelem([0], 2 * length(app.elems)));
            app.light_timer = timer('StartDelay', .25, 'TimerFcn', @(~,~) TimerCallback(app));
        end

        function StartButtonPushed(app, event)
            app.TabGroup.SelectedTab = app.TestTab;
            app.SN = app.SubjectNumberEditField.Value;
            app.Date = app.TestDatePicker.Value;
            app.Tester = app.TesterDropDown.Value;
            [y, Fs] = app.createAudio();
            fn = [datestr(app.Date) '_' app.SN '_' app.Tester];
            audiowrite([fn '.wav'], y, Fs);
            app.audio = audioplayer(y, Fs);
        end
        
        function UIFigureKeyPress(app, event)
            if app.TabGroup.SelectedTab == app.TestTab
                if strcmp(event.Key, 'uparrow')
                   app.UpButtonPushed(event);
                elseif strcmp(event.Key, 'downarrow')
                   app.DownButtonPushed(event);
                end
            end
        end

        function UpButtonPushed(app, event)
            app.LightPanel.BackgroundColor = [0 .375 0];
            second = seconds((datetime - app.tmark));
            app.recordJudge(second, true);
            start(app.light_timer);
        end

        function DownButtonPushed(app, event)
            app.LightPanel.BackgroundColor = [0 .375 0];
            second = seconds((datetime - app.tmark));
            app.recordJudge(second, false);
            start(app.light_timer);
        end
        
        function TimerCallback(app, event)
            app.LightPanel.BackgroundColor = 'white';
        end

        function FinishSignButtonPushed(app, event)
            if strcmp(app.FinishSignButton.Text, 'Start')
                app.FinishSignButton.Text = 'Finish & Sign';
                app.tmark = datetime;
                playblocking(app.audio);
            else
                for idx = 1:length(app.is_noise)
                    if ~app.is_noise(idx)
                        record_idx = app.answer(floor((idx + 1) / 2));
                        app.wrong(record_idx) = app.wrong(record_idx) + 1;
                    end
                end
            
                app.TabGroup.SelectedTab = app.ResultTab;
                fn = [datestr(app.Date) '_' app.SN '_' app.Tester];
                arr = [app.elems -app.elems];
                fileID = fopen([fn '.txt'], 'w');
                for idx = 1:length(app.elems)
                    correct = app.correct(arr(idx)) + app.correct(-arr(idx));
                    wrong = app.wrong(arr(idx)) + app.wrong(-arr(idx));
                    fprintf(fileID, '[%d%% semitone] %.2f%%\n', arr(idx), 100 * correct / (correct + wrong));
                end
                fprintf(fileID, '\n');
                for idx = 1:length(arr)
                    fprintf(fileID, '[Benchmark, %d%%] Correct %d times, Wrong %d times\n', arr(idx), app.correct(arr(idx)), app.wrong(arr(idx)));
                end
                fprintf(fileID, '[Noise] %d times', app.noise);
                fclose(fileID);

                record = app.record;
                save(fn, 'record');
            end
        end
    end

    methods (Access = private)
        
        function recordJudge(app, second, key)
            idx = floor((second + app.SECOND) / (2 * app.SECOND));
            
            y = 0;
            if mod(second, 2 * app.SECOND) >= app.SECOND
                y = app.answer(idx);
            end
            if key; sign = '^'; press = 'up'; else; sign = 'v'; press = 'down'; end
            plot(app.UIAxes, second, y, ['black' sign]);
            
            if idx > 0
               judge = '';
               result_idx = floor(second / app.SECOND);
               record_ans = app.answer(idx);
               record = num2str(record_ans);
               if mod(second, 2 * app.SECOND) <= app.SECOND / 2
                   key = ~key;
                   record = num2str(-record_ans);
               end
               if mod(second, app.SECOND) <= app.SECOND / 2 & ~app.is_noise(result_idx)
                   app.is_noise(result_idx) = true;
                   if key == (record_ans > 0)
                       judge = 'correct';
                       app.correct(record_ans) = app.correct(record_ans) + 1;
                   else
                       judge = 'wrong';
                       app.wrong(record_ans) = app.wrong(record_ans) + 1;
                   end
               else
                   judge = 'noise';
                   app.noise = app.noise + 1;
               end
               app.record = [app.record; {num2str(second) press record judge}];
            end
        end
        
        function [y, Fs] = createAudio(app)
            Fs = 81000;
            raise_semitone = 1000 * 2 ^ (1/12);
            flat_semitone = 1000 * 2 ^ (-1/12);
            freq_map = containers.Map('KeyType', 'int32', 'ValueType', 'double');
            tone_map = containers.Map('KeyType', 'int32', 'ValueType', 'int32');
            wave_map = containers.Map('KeyType', 'int32', 'ValueType', 'any');
            for idx = 1:length(app.elems)
                item = app.elems(idx);
                freq_map(item) = round(1000 - (1000 - raise_semitone) * item / 100);
                freq_map(-item) = round(1000 - (1000 - flat_semitone) * item / 100);
            end
            for freq = freq_map(-100):freq_map(100)
                wave_map(freq) = sin(2 * pi * freq * linspace(1/Fs, 1/freq, round(Fs/freq)));
                tone_map(freq) = length(wave_map(freq));
            end

            base = repmat(wave_map(1000), 1, app.SECOND*1000);
            y = [base];
            repelems = repelem(app.elems, app.REPELEMS);
            arr = [repelems -repelems];
            arr = arr(randperm(length(arr)));
            plot(app.UIAxes, 0:app.SECOND, repelem([0], app.SECOND+1), 'blue');
            for idx = 1:length(arr)
                yy = [];
                rev_yy = [];
                tones = app.SECOND * Fs;
                if arr(idx) < 0; color = 'green'; step = -1; else; color = 'red'; step = 1; end
                plot(app.UIAxes, 2*app.SECOND*idx-app.SECOND:2*app.SECOND*idx, repelem([arr(idx)], app.SECOND+1), color);
                plot(app.UIAxes, 2*app.SECOND*idx:2*app.SECOND*idx+app.SECOND, repelem([0], app.SECOND+1), 'blue');
                for freq = 1000:step:freq_map(arr(idx))
                    tones = tones - 2 * tone_map(freq);
                    yy = [yy wave_map(freq)];
                    rev_yy = [wave_map(freq) rev_yy];
                end
                freq = freq_map(arr(idx));
                yy = [yy repmat(wave_map(freq), 1, round(tones/tone_map(freq))) rev_yy];
                y = [y yy base];
            end
            app.answer = arr;
        end
        
        function createComponents(app)
            mp = get(0, 'MonitorPositions');
            width = mp(3);
            height = mp(4);

            app.UIFigure = uifigure('Visible', 'off');
            app.UIFigure.Position = [0 0 width height];
            app.UIFigure.Name = 'UI Figure';
            app.UIFigure.Visible = 'on';
            app.UIFigure.WindowState = 'fullscreen';
            app.UIFigure.WindowKeyPressFcn = createCallbackFcn(app, @UIFigureKeyPress, true);
            
            app.TabGroup = uitabgroup(app.UIFigure);
            app.TabGroup.Position = mp;
            app.RecordTab = uitab(app.TabGroup);
            app.RecordTab.Title = 'Record';
            app.TestTab = uitab(app.TabGroup);
            app.TestTab.Title = 'Test';
            app.ResultTab = uitab(app.TabGroup);
            app.ResultTab.Title = 'Result';
            app.TabGroup.InnerPosition = [0 0 width height];
            
            app.InstructionTextArea = uitextarea(app.RecordTab, 'Editable', 'off');
            app.InstructionTextArea.FontSize = 20;
            app.InstructionTextArea.Position = [width/4 height/2 width/2 height/4];
            app.InstructionTextArea.Value = {'You will hear a pitch varying sound, press the Up arrow/button if you feel the pitch goes up, if the pitch goes down please press the Down arrow/button.'};

            app.StartButton = uibutton(app.RecordTab, 'push');
            app.StartButton.ButtonPushedFcn = createCallbackFcn(app, @StartButtonPushed, true);
            app.StartButton.FontSize = 24;
            app.StartButton.FontWeight = 'bold';
            app.StartButton.Position = [7*width/16 height/16 width/8 height/16];
            app.StartButton.Text = 'Start';

            app.SubjectNumberLabel = uilabel(app.RecordTab);
            app.SubjectNumberLabel.FontSize = 18;
            app.SubjectNumberLabel.HorizontalAlignment = 'right';
            app.SubjectNumberLabel.Position = [5*width/16 3*height/8 width/8 height/24];
            app.SubjectNumberLabel.Text = 'Subject number';

            app.SubjectNumberEditField = uieditfield(app.RecordTab, 'text');
            app.SubjectNumberEditField.FontSize = 18;
            app.SubjectNumberEditField.Position = [15*width/32 3*height/8 width/8 height/24];

            app.TesterLabel = uilabel(app.RecordTab);
            app.TesterLabel.FontSize = 18;
            app.TesterLabel.HorizontalAlignment = 'right';
            app.TesterLabel.Position = [5*width/16 5*height/16 width/8 height/24];
            app.TesterLabel.Text = 'Tester';

            app.TesterDropDown = uidropdown(app.RecordTab);
            app.TesterDropDown.FontSize = 18;
            app.TesterDropDown.Items = {'Jason', 'Meow'};
            app.TesterDropDown.Position = [15*width/32 5*height/16 width/8 height/24];
            app.TesterDropDown.Value = 'Jason';
            
            app.TestDateLabel = uilabel(app.RecordTab);
            app.TestDateLabel.FontSize = 18;
            app.TestDateLabel.HorizontalAlignment = 'right';
            app.TestDateLabel.Position = [5*width/16 height/4 width/8 height/24];
            app.TestDateLabel.Text = 'Test date';
            
            app.TestDatePicker = uidatepicker(app.RecordTab);
            app.TestDatePicker.DisplayFormat = 'yyyy-MM-dd';
            app.TestDatePicker.FontSize = 18;
            app.TestDatePicker.Position = [15*width/32 height/4 width/8 height/24];
            app.TestDatePicker.Value = datetime('today');
            
            app.UpButton = uibutton(app.TestTab, 'push');
            app.UpButton.ButtonPushedFcn = createCallbackFcn(app, @UpButtonPushed, true);
            app.UpButton.FontSize = 36;
            app.UpButton.Position = [width/16 height/4 3*width/8 height/2];
            app.UpButton.Text = 'Up';

            app.DownButton = uibutton(app.TestTab, 'push');
            app.DownButton.ButtonPushedFcn = createCallbackFcn(app, @DownButtonPushed, true);
            app.DownButton.FontSize = 36;
            app.DownButton.Position = [9*width/16 height/4 3*width/8 height/2];
            app.DownButton.Text = 'Down';
            
            app.LightPanel = uipanel(app.TestTab);
            app.LightPanel.BackgroundColor = 'white';
            app.LightPanel.Position = [15*width/32 7*height/8 width/16 height/16];
            
            app.FinishSignButton = uibutton(app.TestTab, 'push');
            app.FinishSignButton.ButtonPushedFcn = createCallbackFcn(app, @FinishSignButtonPushed, true);
            app.FinishSignButton.FontSize = 24;
            app.FinishSignButton.FontWeight = 'bold';
            app.FinishSignButton.Position = [7*width/16 height/16 width/8 height/16];
            app.FinishSignButton.Text = 'Start';

            app.UIAxes = uiaxes(app.ResultTab);
            title(app.UIAxes, 'Title')
            xlabel(app.UIAxes, 'Time')
            ylabel(app.UIAxes, 'Freq')
            hold(app.UIAxes);
            app.UIAxes.Position = [width/8 height/16 3*width/4 3*height/4];
        end
        
    end

    methods (Access = public)
        
        function app = sliding_2AC
            createComponents(app)
            registerApp(app, app.UIFigure)
            runStartupFcn(app, @startupFcn)
            if nargout == 0
                clear app
            end
        end

        function delete(app)
            delete(app.UIFigure)
        end
        
    end
end