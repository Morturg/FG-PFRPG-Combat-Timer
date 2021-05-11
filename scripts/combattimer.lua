

-- Timer variables
local timerEnabled = false;
local timerRunning = false;
local startTime = 0;
local timePassed = 0;
local timerDuration = 60;
local timerType = 0;

-- Protocol variables
local lastEpoch = 0;

-- Display variables
local timerDisplay = nil;
local timerStatus = nil;
local pingEnabled = 1;

-- Local Activation Hook
old_requestActivation = nil;


----------------------------------------
--       Utility Functions
----------------------------------------

function max(a, b)
	if a > b then
		return a
	else
		return b
	end
end

-- -- Are you fucking kidding me, Lua? 
function tablesize(t)
	count = 0
	for k,v in pairs(t) do
		 count = count + 1
	end
	return count
end

function parseMessage(msg)
	i, i = string.find(msg, "|")
	if i == nil then
		return nil
	end
	
	cmd = string.sub(msg, 0, i-1)
	msg = string.sub(msg, i+1)

	i, i = string.find(msg, "|")
	if i == nil then
		return nil
	end

	gen = string.sub(msg, 0, i-1)
	param = string.sub(msg, i+1)
	
	gen = tonumber(gen)
	param = tonumber(param)
	
	return cmd, gen, param
end

----------------------------------------
--      Event Callback Methods
----------------------------------------
function onInit()
	-- Debug.console("onInit - ct_combat_timer");
	OOBManager.registerOOBMsgHandler("ct_timer", receiveOOBMessage)
	if Session.IsHost == true then
		-- ct_active.lua directly activates database nodes and does not inform our callback hooks
		-- that the turn is changing.  For my GM, who drags the turn tracker around, this breaks
		-- the module.  So, instead we hook the CombatManager.requestActivation (which is common
		-- to both turn transition paths) to reset the timer.
		
		-- So anyway, this is horrible and I should probably be shot for doing this.
		-- What else is new?
		
		-- CombatManager.setCustomTurnStart(customTurnStart);
		old_requestActivation = CombatManager.requestActivation;
		CombatManager.requestActivation = requestActivationHook;
	end
	
	-- Set default values for the timer (Doesn't start the timer if it's
	-- not running).
	resetTimer();
end

function onClose()
	if old_requestActivation ~= nil then
		CombatManager.requestActivation = old_requestActivation;
	end
	
	-- Stop message notifications
	OOBManager.registerOOBMsgHandler("ct_timer", nil)

	-- Stop the timer if it's running (directly set variables as 
	-- stopTimer is not safe to call while FG is closing)
	lastEpoch = 0;
	timerRunning = false;
	timerEnabled = false;
end

function onDoubleClick( x, y )
	-- Debug.console("onDoubleClick");

	resetTimer();
end

function requestActivationHook(nodeEntry, bSkipBell)
	
	-- We'll still get turn notifications even if the window is closed.
	-- resetTimer should do the right thing.
	-- Debug.console("customTurnStart", nodeCT);

	resetTimer();
	
	return old_requestActivation(nodeEntry, bSkipBell);
	
end
----------------------------------------
--      Subwindow callbacks
----------------------------------------
function registerTimerDisplay(display)
	-- Debug.console("registerTimerDisplay", display);
	timerDisplay = display;
end

function registerTimerStatus(status)
	-- Debug.console("registerTimerStatus", status);
	timerStatus = status;
end

----------------------------------------
--      Helper functions
----------------------------------------

function updateUI(timerValue)
	if timerStatus ~= nil then
		timerStatus.update();
	end

	if timerDisplay ~= nil and timerDisplay.setValue ~= nil and timerValue ~= nil then
		-- Debug.console("Updating timer display: ".. timerValue .. " --> " .. formatTimer(timerValue))
		timerDisplay.setValue(formatTimer(timerValue));
	end
end

function formatTimer(seconds)
	if seconds < 0 then
		seconds = 0
	end
	minutes = seconds / 60;
	seconds = seconds % 60;
	return string.format("%02d:%02d", minutes, seconds);
end

----------------------------------------
--      Accessor functions
----------------------------------------

function isTimerEnabled()
	return timerEnabled;
end

function isTimerRunning()
	return timerRunning;
end

function getTimerType()
	return timerType;
end

function setTimerType(tType)
	-- Only reset timer when values change
	doReset = false
	if timerType ~= tType then
		doReset = true
	end
	
	timerType = tType;
	
	if doReset then
		resetTimer();
	end
end

function setTimerDuration(tTime)
	-- Only reset timer when values change
	doReset = false
	if timerDuration ~= tTime then
		doReset = true
	end

	timerDuration = tTime;

	if doReset then
		resetTimer();
	end
end

function getTimerDuration()
	return timerDuration;
end

function setPingEnabled(enabled)
	pingEnabled = enabled;
end

function getPingEnabled()
	return pingEnabled;
end


function toggleTimer()
	-- Debug.console("toggleTimer - ct_combat_timer");
	
	if Session.IsHost == false then
		-- Debug.console("toggleTimer - Error: Only host can toggle the timer");
		return
	end
	
	setTimerEnabled(not timerEnabled);
end

function getTimeElapsed()
	timeSoFar = 0
	if timerRunning then	
		timeSoFar = (os.time() - startTime)
	end
	
	result = 0
	
	-- Calculate timer display based upon the type of timer it is
	if timerType == 0 then -- Count Down
		result = timerDuration - timePassed - timeSoFar 
	else -- Count Up
		result = timePassed + timeSoFar;
	end
	
	return result
end

function setTimerEnabled(bEnabled)
	-- Debug.console("Combat Timer enabled!");

	timerEnabled = bEnabled;
	
	enable(timerEnabled);
	
	if bEnabled == true then
		startTimer();
	else
		stopTimer();
	end
end


----------------------------------------
--      Timer Protocol
----------------------------------------

-- Host Messages:
-- 	CT_START
-- 	CT_STOP
-- 	CT_UPDATE
-- 	CT_PING
--	CT_ENABLE

-- User Messages:
-- 	CT_PONG

function startTimer()
	-- Debug.console("Combat Timer started!");

	if Session.IsHost == false or timerRunning == true then
		return;
	end
	
	if tablesize(User.getActiveUsers()) < 1 then
		warningmsg = {};
		warningmsg.text = "WARNING: Combat Timer only ticks with multiple users connected.";
		warningmsg.sender = "CombatTimer"
		Comm.addChatMessage(warningmsg)
	end

	-- Send a notificaiton that the timer has started up again
	timerVal = getTimeElapsed()
	start(timerVal)

	-- Only start ticking if we have time left on the timer
	if (timerType == 0 and timerVal > 0) or (timerType == 1) then
		timerRunning = true;
		startTime = os.time(); 
		lastEpoch = 0;

		updateUI(timerVal);
		
		ping(getTimeElapsed(), lastEpoch+1)
	end
	
end

function stopTimer()
	-- Debug.console("Combat Timer stopped!");

	if timerRunning == false then
		return;
	end

	timerRunning = false;

	-- Reset remaining expiration from the startTime
	timePassed = timePassed + os.time() - startTime;
	
	updateUI();
	
	-- Allow the code to get this far on if Session.IsHost == true.  This
	-- function is called on de-initialization.
	if Session.IsHost == false then
		return
	end
	
	stop(getTimeElapsed())
end

function resetTimer()

	-- Debug.console("Combat Timer reset!");

	if Session.IsHost == false then
		return;
	end
	
	
	-- Only meaningful if resetTimer is called while timerRunning == true
	startTime = os.time(); 
	timePassed = 0;
	timerValue = getTimeElapsed()
	
	updateUI(timerValue);
	
	-- Update the remote timer to the current value
	update(timerValue)
	
	if timerEnabled == true then
		-- Set timerRunning to true regardless of original value
		timerRunning = true 
		ping(timerValue, lastEpoch+1);
	end
end



-- Also technically a callback, but used to receive OOB protocol messages
function receiveOOBMessage(msg)
	-- Debug.console(msg.type, msg.text, msg.sender);
	
	cmd, gen, param = parseMessage(msg.text);
	
	if Session.IsHost then
		if cmd == "CT_PONG" and lastEpoch < gen and timerRunning then
			-- Only send a Ping to keep the timer running if the timer is going to keep counting
			lastEpoch = gen
			timeleft = getTimeElapsed();
			
			updateUI(timeleft);

			if timeleft >= 0 then 
				ping(timeleft, lastEpoch+1);
			else
				-- Our timer has ended.  Shut off the timer and update timePassed
				-- Reset remaining expiration from the startTime
				timerRunning = false;
				timePassed = timePassed + os.time() - startTime;

				-- Ring the bell if its enabled
				if pingEnabled ~= 0 then
					User.ringBell() -- Props to Nickademus for this
				end
				
			end
		end
	else -- not Session.IsHost 
		if cmd == "CT_PING" and lastEpoch < gen then
			-- Send a response message to keep the timer running
			-- Don't worry about whether the server is running. Just respond
			-- and let the server deal with the state
			lastEpoch = gen
			
			pong(msg.sender, gen);
			
			-- Update the view with the latest numbers from the server
			
			updateUI(param);
			
		elseif cmd == "CT_ENABLE" then
			if param == 0 then
				timerEnabled = false
			else
				timerEnabled = true
			end

			-- Update the view with the latest numbers from the server
			updateUI();
		elseif cmd == "CT_START" then
			lastEpoch = gen

			timerRunning = true;

			-- Update the view with the latest numbers from the server
			updateUI(param);
			
		elseif cmd == "CT_UPDATE" then
			-- Update the view with the latest numbers from the server
			updateUI(param);
			
		elseif cmd == "CT_STOP" then
			timerRunning = false;
	
			-- Update the view with the latest numbers from the server
			updateUI(param);
		end
	end
end


----------------------------------------
--      Send Message Helpers
----------------------------------------

function start(param)
	-- Only update the startTimer
	startTime = os.time();
	
	startmsg = {};
	startmsg.type = "ct_timer"
	startmsg.text = "CT_START" .. "|" .. 0 .. "|" .. param;
	startmsg.secret = true;
	startmsg.sender = User.getUsername()
	
	-- Debug.console("Sending startmsg");

	Comm.deliverOOBMessage(startmsg);
end

function update(param)
	updatemsg = {};
	updatemsg.type = "ct_timer"
	updatemsg.text = "CT_UPDATE" .. "|" .. 0 .. "|" .. param;
	updatemsg.secret = true;
	updatemsg.sender = User.getUsername()
	
	-- Debug.console("Sending updatemsg");

	Comm.deliverOOBMessage(updatemsg);
end

function stop(param)
	stopmsg = {};
	stopmsg.type = "ct_timer"
	stopmsg.text = "CT_STOP" .. "|" .. 0 .. "|" .. param;
	stopmsg.secret = true;
	stopmsg.sender = User.getUsername()
	
	-- Debug.console("Sending stopmsg");
	
	Comm.deliverOOBMessage(stopmsg);
end

function enable(param)
	enablemsg = {};
	enablemsg.type = "ct_timer"
	if param == false then
		enablemsg.text = "CT_ENABLE" .. "|" .. 0 .. "|" .. "0";
	else
		enablemsg.text = "CT_ENABLE" .. "|" .. 0 .. "|" .. "1";
	end
	enablemsg.secret = true;
	enablemsg.sender = User.getUsername()
	
	-- Debug.console("Sending enablemsg");

	Comm.deliverOOBMessage(enablemsg);
end

function ping(param, epoch)
	if timerRunning == false then
		return;
	end
	
	pingmsg = {};
	pingmsg.type = "ct_timer"
	pingmsg.text = "CT_PING" .. "|" .. epoch .. "|" .. param;
	pingmsg.secret = true;
	pingmsg.sender = User.getUsername()
	
	-- Debug.console("Sending pingmsg");
	
	Comm.deliverOOBMessage(pingmsg);
end

function pong(user, epoch)
	if timerRunning == false then
		return;
	end
	
	pongmsg = {}
	pongmsg.type = "ct_timer"
	pongmsg.text = "CT_PONG" .. "|" .. epoch .. "|" .. 0;
	pongmsg.secret = true;
	pongmsg.sender = User.getUsername()
	
	-- Debug.console("Sending pongmsg");
	
	Comm.deliverOOBMessage(pongmsg, user);
end