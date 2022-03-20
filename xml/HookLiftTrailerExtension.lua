--[[
HookLiftTrailerExtension

Script to allow set two unload animations on an HKL Truck/Trailer

@Author:	Ifko[nator]
@Date:		26.02.2022
@Version:	3.0

@History:	v1.0 @24.09.2017 - initial release in FS 17
			---------------------------------------------------------------------------
			v2.0 @28.12.2019 - convert to FS 19
			---------------------------------------------------------------------------
			V2.5 @09.02.2020 - added option to change between long and short containers
			---------------------------------------------------------------------------
			v3.0 @26.02.2022 - convert to FS 22
]]

HookLiftTrailerExtension = {};
HookLiftTrailerExtension.currentModName = g_currentModName;

function HookLiftTrailerExtension.initSpecialization()
	local schemaSavegame = Vehicle.xmlSchemaSavegame;

	schemaSavegame:register(XMLValueType.BOOL, "vehicles.vehicle(?)." .. HookLiftTrailerExtension.currentModName .. ".hookLiftTrailerExtension#unloadToTrailer", "Is container unload to trailer active.", false);
	schemaSavegame:register(XMLValueType.BOOL, "vehicles.vehicle(?)." .. HookLiftTrailerExtension.currentModName .. ".hookLiftTrailerExtension#isSmallContainer", "Is small container size active.", false);
end;

function HookLiftTrailerExtension.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(HookLiftTrailer, specializations); 
end;

function HookLiftTrailerExtension.registerEventListeners(vehicleType)
	local functionNames = {
		"onLoad",
		"onUpdate",
		"onWriteStream",
		"onReadStream",
		"onRegisterActionEvents"
	};

	for _, functionName in ipairs(functionNames) do
		SpecializationUtil.registerEventListener(vehicleType, functionName, HookLiftTrailerExtension);
	end;
end;

function HookLiftTrailerExtension.registerFunctions(vehicleType)
	local functionNames = {
		"setContainerSize",
		"setUnloadState"
	};
	
	for _, functionName in ipairs(functionNames) do
		SpecializationUtil.registerFunction(vehicleType, functionName, HookLiftTrailerExtension[functionName]);
	end;
end;

function HookLiftTrailerExtension.registerOverwrittenFunctions(vehicleType)
	local functionNames = {
		"getIsFoldAllowed"
	};
	
	for _, functionName in ipairs(functionNames) do
		SpecializationUtil.registerOverwrittenFunction(vehicleType, functionName, HookLiftTrailerExtension[functionName]);
	end;
end;

function HookLiftTrailerExtension:onLoad(savegame)
	local specHookLiftTrailer = self.spec_hookLiftTrailer;
	
	specHookLiftTrailer.unloadToTrailer = false;
	specHookLiftTrailer.isSmallContainer = false;
	
	if savegame ~= nil and not savegame.resetVehicles then
		specHookLiftTrailer.unloadToTrailer = savegame.xmlFile:getValue(savegame.key .. "." .. HookLiftTrailerExtension.currentModName .. ".hookLiftTrailerExtension#unloadToTrailer", specHookLiftTrailer.unloadToTrailer);
		specHookLiftTrailer.isSmallContainer = savegame.xmlFile:getValue(savegame.key .. "." .. HookLiftTrailerExtension.currentModName .. ".hookLiftTrailerExtension#isSmallContainer", specHookLiftTrailer.isSmallContainer);
	end;
	
	specHookLiftTrailer.unloadToTrailerOld = specHookLiftTrailer.unloadToTrailer;
	specHookLiftTrailer.isSmallContainerOld = not specHookLiftTrailer.isSmallContainer;
	specHookLiftTrailer.hasFinishedFirstRun = false;
	
	self:setUnloadState(specHookLiftTrailer.unloadToTrailer, false);
	self:setContainerSize(specHookLiftTrailer.isSmallContainer, false);
	
	local xmlFile = loadXMLFile("vehicle", self.xmlFile.filename);

	specHookLiftTrailer.switchUnloadStateAnimation = Utils.getNoNil(getXMLString(xmlFile, "vehicle.hookLiftTrailer.switchUnloadStateAnimation#name"), "notDefined");
	specHookLiftTrailer.handRotPart = I3DUtil.indexToObject(self.components, getXMLString(xmlFile, "vehicle.hookLiftTrailer.handRotPart#node"), self.i3dMappings);
	specHookLiftTrailer.unfoldHandToTrailerAnimation = Utils.getNoNil(getXMLString(xmlFile, "vehicle.hookLiftTrailer.unfoldHandToTrailerAnimation#name"), "unfoldHandToTrailer");
	specHookLiftTrailer.unfoldHandToGroundAnimation = specHookLiftTrailer.refAnimation;

	specHookLiftTrailer.unfoldHandToTrailerAnimationSmall = Utils.getNoNil(getXMLString(xmlFile, "vehicle.hookLiftTrailer.unfoldHandToTrailerAnimationSmall#name"), "unfoldHandToTrailerSmall");
	specHookLiftTrailer.unfoldHandToGroundAnimationSmall = Utils.getNoNil(getXMLString(xmlFile, "vehicle.hookLiftTrailer.unfoldHandToGroundAnimationSmall#name"), "unfoldHandToGroundSmall");
	specHookLiftTrailer.switchContainerSizeAnimation = Utils.getNoNil(getXMLString(xmlFile, "vehicle.hookLiftTrailer.switchContainerSizeAnimation#name"), "notDefined");

	delete(xmlFile);
end;

function HookLiftTrailerExtension:onUpdate(dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
	local specHookLiftTrailer = self.spec_hookLiftTrailer;
	local specFoldable = self.spec_foldable;

	local changeUnloadingTypeButton = specHookLiftTrailer.actionEvents[InputAction.CHANGE_UNLOADING_TYPE_BUTTON];
	local changeContainerSizeButton = specHookLiftTrailer.actionEvents[InputAction.CHANGE_CONTAINER_SIZE_BUTTON];

	local currentUnloadText = g_i18n:getText("UNLOAD_TO_GROUND_IS_ACTIVE");
	local currentContainerSizeText = g_i18n:getText("CONTAINER_SIZE_BIG");

	local animDirection = -1;
	local rotX, _, _ = getRotation(specHookLiftTrailer.handRotPart);
		
	local isArmUnfolded = rotX < 0 and not self:getIsAnimationPlaying(specHookLiftTrailer.refAnimation);

	specHookLiftTrailer.refAnimation = specHookLiftTrailer.unfoldHandToGroundAnimation;

	if specHookLiftTrailer.isSmallContainer then
		specHookLiftTrailer.refAnimation = specHookLiftTrailer.unfoldHandToGroundAnimationSmall;
	end;
	
	for _, foldingPart in pairs(specFoldable.foldingParts) do
		foldingPart.animationName = specHookLiftTrailer.unfoldHandToGroundAnimation;

		if specHookLiftTrailer.isSmallContainer then
			foldingPart.animationName = specHookLiftTrailer.unfoldHandToGroundAnimationSmall;
		end;
	end;
	
	if specHookLiftTrailer.unloadToTrailer then
		currentUnloadText = g_i18n:getText("UNLOAD_TO_TRAILER_IS_ACTIVE");

		specHookLiftTrailer.refAnimation = specHookLiftTrailer.unfoldHandToTrailerAnimation;

		if specHookLiftTrailer.isSmallContainer then
			specHookLiftTrailer.refAnimation = specHookLiftTrailer.unfoldHandToTrailerAnimationSmall;
		end;

		for _, foldingPart in pairs(specFoldable.foldingParts) do
			foldingPart.animationName = specHookLiftTrailer.unfoldHandToTrailerAnimation;

			if specHookLiftTrailer.isSmallContainer then
				foldingPart.animationName = specHookLiftTrailer.unfoldHandToTrailerAnimationSmall;
			end;
		end;
	end;

	if specHookLiftTrailer.isSmallContainer then
		currentContainerSizeText = g_i18n:getText("CONTAINER_SIZE_SMALL");

		animDirection = 1;
	end;

	if not specHookLiftTrailer.hasFinishedFirstRun then
		if not isArmUnfolded and specHookLiftTrailer.switchContainerSizeAnimation ~= "notDefined" then
			self:playAnimation(specHookLiftTrailer.switchContainerSizeAnimation, animDirection, nil, true);
			
			AnimatedVehicle.updateAnimationByName(self, specHookLiftTrailer.switchContainerSizeAnimation, 9999999);
		end;

		specHookLiftTrailer.hasFinishedFirstRun = true;
	end;

	if not isArmUnfolded and specHookLiftTrailer.switchContainerSizeAnimation ~= "notDefined" then
		if specHookLiftTrailer.isSmallContainerOld ~= specHookLiftTrailer.isSmallContainer and not self:getIsAnimationPlaying(specHookLiftTrailer.refAnimation) then
			self:playAnimation(specHookLiftTrailer.switchContainerSizeAnimation, animDirection, nil, true);

			specHookLiftTrailer.isSmallContainerOld = specHookLiftTrailer.isSmallContainer;
		end;
	end;

	if specHookLiftTrailer.switchUnloadStateAnimation ~= "notDefined" then
		local animDirection = -1;
		local currentRefAnimation = specHookLiftTrailer.unfoldHandToGroundAnimation;
		local oldRefAnimation = specHookLiftTrailer.unfoldHandToTrailerAnimation;

		if specHookLiftTrailer.isSmallContainer then
			currentRefAnimation = specHookLiftTrailer.unfoldHandToGroundAnimationSmall;
			oldRefAnimation = specHookLiftTrailer.unfoldHandToTrailerAnimationSmall;
		end;

		if specHookLiftTrailer.unloadToTrailer then
			animDirection = 1;
			currentRefAnimation = specHookLiftTrailer.unfoldHandToTrailerAnimation;
			oldRefAnimation = specHookLiftTrailer.unfoldHandToGroundAnimation;

			if specHookLiftTrailer.isSmallContainer then
				currentRefAnimation = specHookLiftTrailer.unfoldHandToTrailerAnimationSmall;
				oldRefAnimation = specHookLiftTrailer.unfoldHandToGroundAnimationSmall;
			end;
		end;


		if isArmUnfolded then
			if specHookLiftTrailer.unloadToTrailerOld ~= specHookLiftTrailer.unloadToTrailer then
				self:playAnimation(specHookLiftTrailer.switchUnloadStateAnimation, animDirection, nil, true);

				specHookLiftTrailer.unloadToTrailerOld = specHookLiftTrailer.unloadToTrailer;
			end;
			
			if self:getAnimationTime(currentRefAnimation) == 0 and not self:getIsAnimationPlaying(specHookLiftTrailer.switchUnloadStateAnimation) then
				self:setAnimationTime(currentRefAnimation, 1);
			end;
		else
			if self:getAnimationTime(currentRefAnimation) == 1 and not self:getIsAnimationPlaying(specHookLiftTrailer.switchUnloadStateAnimation) then
				self:setAnimationTime(currentRefAnimation, 0);
			end;
		end;
		
		if rotX == 0 and not self:getIsAnimationPlaying(specHookLiftTrailer.refAnimation) then
			if self:getAnimationTime(oldRefAnimation) == 1 then
				self:setAnimationTime(oldRefAnimation, 0);
			end;

			if specHookLiftTrailer.unloadToTrailerOld ~= specHookLiftTrailer.unloadToTrailer then
				specHookLiftTrailer.unloadToTrailerOld = specHookLiftTrailer.unloadToTrailer;
			end;
		end;

		--renderText(0.35, 0.5, 0.02, "rotX = " .. math.ceil(math.deg(rotX)));
		--renderText(0.35, 0.48, 0.02, "refAnimation time = " .. self:getAnimationTime(currentRefAnimation));
		--renderText(0.35, 0.46, 0.02, "isArmUnfolded = " .. tostring(isArmUnfolded));
		--renderText(0.35, 0.44, 0.02, "unloadToTrailerOld = " .. tostring(specHookLiftTrailer.unloadToTrailerOld));
		--renderText(0.35, 0.42, 0.02, "unloadToTrailer = " .. tostring(specHookLiftTrailer.unloadToTrailer));
		--renderText(0.35, 0.4, 0.02, "currentRefAnimation = " .. currentRefAnimation);
		--renderText(0.35, 0.38, 0.02, "is playing switch unload state = " .. tostring(self:getIsAnimationPlaying(specHookLiftTrailer.switchUnloadStateAnimation)));
	end;
	
	local allowShowButton = not self:getIsAnimationPlaying(specHookLiftTrailer.refAnimation)
		and not self:getIsAnimationPlaying(specHookLiftTrailer.switchUnloadStateAnimation)
	;

	if changeUnloadingTypeButton ~= nil then
		g_currentMission:addExtraPrintText(currentUnloadText);

		g_inputBinding:setActionEventActive(changeUnloadingTypeButton.actionEventId, allowShowButton);
		g_inputBinding:setActionEventTextVisibility(changeUnloadingTypeButton.actionEventId, allowShowButton);
	end;

	if changeContainerSizeButton ~= nil then
		if specHookLiftTrailer.switchContainerSizeAnimation ~= "notDefined" then
			g_currentMission:addExtraPrintText(currentContainerSizeText);
		end;

		allowShowButton = allowShowButton and not isArmUnfolded and specHookLiftTrailer.switchContainerSizeAnimation ~= "notDefined";

		g_inputBinding:setActionEventActive(changeContainerSizeButton.actionEventId, allowShowButton);
		g_inputBinding:setActionEventTextVisibility(changeContainerSizeButton.actionEventId, allowShowButton);
	end;

	self:raiseActive();
end;

function HookLiftTrailerExtension:setUnloadState(unloadState, noEventSend)
	local specHookLiftTrailer = self.spec_hookLiftTrailer;

	if unloadState ~= specHookLiftTrailer.unloadToTrailer then	
		specHookLiftTrailer.unloadToTrailer = unloadState;
		
		HookLiftTrailerExtensionUnloadStateEvent.sendEvent(self, unloadState, noEventSend);
	end;
end;

function HookLiftTrailerExtension:setContainerSize(isSmallContainer, noEventSend)
	local specHookLiftTrailer = self.spec_hookLiftTrailer;

	if isSmallContainer ~= specHookLiftTrailer.isSmallContainer then	
		specHookLiftTrailer.isSmallContainer = isSmallContainer;
		
		HookLiftTrailerExtensionContainerSizeEvent.sendEvent(self, isSmallContainer, noEventSend);
	end;
end;

function HookLiftTrailerExtension:getIsFoldAllowed(superFunc, direction, onAiTurnOn)
    local specHookLiftTrailer = self.spec_hookLiftTrailer;
	
	if self:getAnimationTime(specHookLiftTrailer.unloadingAnimation) > 0 or self:getIsAnimationPlaying(specHookLiftTrailer.switchUnloadStateAnimation) then
        return false;
	end;
	
    return superFunc(self, direction, onAiTurnOn);
end;

function HookLiftTrailerExtension:onWriteStream(streamId, connection)
	if not connection:getIsServer() then 
		local specHookLiftTrailer = self.spec_hookLiftTrailer;
		
		if specHookLiftTrailer.unloadToTrailer ~= nil then
			streamWriteBool(streamId, specHookLiftTrailer.unloadToTrailer);
		end;

		if specHookLiftTrailer.isSmallContainer ~= nil then
			streamWriteBool(streamId, specHookLiftTrailer.isSmallContainer);
		end;
	end;
end;

function HookLiftTrailerExtension:onReadStream(streamId, connection)
	if connection:getIsServer() then
		local specHookLiftTrailer = self.spec_hookLiftTrailer;
		
		if specHookLiftTrailer.unloadToTrailer ~= nil then
			specHookLiftTrailer.unloadToTrailer = streamReadBool(streamId);
		end;

		if specHookLiftTrailer.isSmallContainer ~= nil then
			specHookLiftTrailer.isSmallContainer = streamReadBool(streamId);
		end;
	end;
end;

function HookLiftTrailerExtension:onRegisterActionEvents(isActiveForInput, isActiveForInputIgnoreSelection)
	if self.isClient then
		local specHookLiftTrailer = self.spec_hookLiftTrailer;
        
		self:clearActionEventsTable(specHookLiftTrailer.actionEvents);

		if self:getIsActiveForInput(true) then
			local inputs = {
				"CHANGE_CONTAINER_SIZE_BUTTON",
				"CHANGE_UNLOADING_TYPE_BUTTON"
			};
			
			for _, input in ipairs(inputs) do
				local _, actionEventId = self:addActionEvent(specHookLiftTrailer.actionEvents, InputAction[input], self, HookLiftTrailerExtension.actionEventChangeUnloadState, false, true, false, true, nil);
			
				g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_NORMAL);
				g_inputBinding:setActionEventTextVisibility(actionEventId, true);
				g_inputBinding:setActionEventActive(actionEventId, true);
			end;
		end;
	end;
end;

function HookLiftTrailerExtension.actionEventChangeUnloadState(self, actionName, inputValue, callbackState, isAnalog)
	local specHookLiftTrailer = self.spec_hookLiftTrailer;

	if actionName == "CHANGE_CONTAINER_SIZE_BUTTON" then
		self:setContainerSize(not specHookLiftTrailer.isSmallContainer);
	else
		self:setUnloadState(not specHookLiftTrailer.unloadToTrailer);
	end;
end;

function HookLiftTrailerExtension:saveToXMLFile(xmlFile, key)
	local specHookLiftTrailer = self.spec_hookLiftTrailer;
	
	xmlFile:setValue(key .. "#unloadToTrailer", specHookLiftTrailer.unloadToTrailer);
	xmlFile:setValue(key .. "#isSmallContainer", specHookLiftTrailer.isSmallContainer);
end;

--------------------------------------------------------------------------------------------------------
--## MP Stuff
--## set unload state
--------------------------------------------------------------------------------------------------------

HookLiftTrailerExtensionUnloadStateEvent = {};
HookLiftTrailerExtensionUnloadStateEvent_mt = Class(HookLiftTrailerExtensionUnloadStateEvent, Event);

InitEventClass(HookLiftTrailerExtensionUnloadStateEvent, "HookLiftTrailerExtensionUnloadStateEvent");

function HookLiftTrailerExtensionUnloadStateEvent.emptyNew()
	local self = Event.new(HookLiftTrailerExtensionUnloadStateEvent_mt);
    
	return self;
end;

function HookLiftTrailerExtensionUnloadStateEvent.new(hookLiftTrailer, unloadState)
	local self = HookLiftTrailerExtensionUnloadStateEvent.emptyNew();
	
	self.hookLiftTrailer = hookLiftTrailer;
	self.unloadState = unloadState;
	
	return self;
end;

function HookLiftTrailerExtensionUnloadStateEvent:readStream(streamId, connection)
	self.hookLiftTrailer = NetworkUtil.readNodeObject(streamId);
	self.unloadState = streamReadBool(streamId);

    self:run(connection);
end;

function HookLiftTrailerExtensionUnloadStateEvent:writeStream(streamId, connection)
	NetworkUtil.writeNodeObject(streamId, self.hookLiftTrailer);
	streamWriteBool(streamId, self.unloadState);
end;

function HookLiftTrailerExtensionUnloadStateEvent:run(connection)
	if self.hookLiftTrailer.setUnloadState ~= nil then
		self.hookLiftTrailer:setUnloadState(self.unloadState, true);
	end;
	
	if not connection:getIsServer() then
		g_server:broadcastEvent(HookLiftTrailerExtensionUnloadStateEvent.new(self.hookLiftTrailer, self.unloadState), nil, connection, self.hookLiftTrailer);
	end;
end;

function HookLiftTrailerExtensionUnloadStateEvent.sendEvent(hookLiftTrailer, unloadState, noEventSend)
	if noEventSend == nil or noEventSend == false then
		if g_server ~= nil then
			g_server:broadcastEvent(HookLiftTrailerExtensionUnloadStateEvent.new(hookLiftTrailer, unloadState), nil, nil, hookLiftTrailer);
		else
			g_client:getServerConnection():sendEvent(HookLiftTrailerExtensionUnloadStateEvent.new(hookLiftTrailer, unloadState));
		end;
	end;
end;

--------------------------------------------------------------------------------------------------------
--## set container size
--------------------------------------------------------------------------------------------------------

HookLiftTrailerExtensionContainerSizeEvent = {};
HookLiftTrailerExtensionContainerSizeEvent_mt = Class(HookLiftTrailerExtensionContainerSizeEvent, Event);

InitEventClass(HookLiftTrailerExtensionContainerSizeEvent, "HookLiftTrailerExtensionContainerSizeEvent");

function HookLiftTrailerExtensionContainerSizeEvent.emptyNew()
	local self = Event.new(HookLiftTrailerExtensionContainerSizeEvent_mt);
    
	return self;
end;

function HookLiftTrailerExtensionContainerSizeEvent.new(hookLiftTrailer, isSmallContainer)
	local self = HookLiftTrailerExtensionContainerSizeEvent.emptyNew();
	
	self.hookLiftTrailer = hookLiftTrailer;
	self.isSmallContainer = isSmallContainer;
	
	return self;
end;

function HookLiftTrailerExtensionContainerSizeEvent:readStream(streamId, connection)
	self.hookLiftTrailer = NetworkUtil.readNodeObject(streamId);
	self.isSmallContainer = streamReadBool(streamId);

    self:run(connection);
end;

function HookLiftTrailerExtensionContainerSizeEvent:writeStream(streamId, connection)
	NetworkUtil.writeNodeObject(streamId, self.hookLiftTrailer);
	streamWriteBool(streamId, self.isSmallContainer);
end;

function HookLiftTrailerExtensionContainerSizeEvent:run(connection)
	if self.hookLiftTrailer.setContainerSize ~= nil then
		self.hookLiftTrailer:setContainerSize(self.isSmallContainer, true);
	end;
	
	if not connection:getIsServer() then
		g_server:broadcastEvent(HookLiftTrailerExtensionContainerSizeEvent.new(self.isSmallContainer, self.isSmallContainer), nil, connection, self.hookLiftTrailer);
	end;
end;

function HookLiftTrailerExtensionContainerSizeEvent.sendEvent(hookLiftTrailer, isSmallContainer, noEventSend)
	if noEventSend == nil or noEventSend == false then
		if g_server ~= nil then
			g_server:broadcastEvent(HookLiftTrailerExtensionContainerSizeEvent.new(hookLiftTrailer, isSmallContainer), nil, nil, hookLiftTrailer);
		else
			g_client:getServerConnection():sendEvent(HookLiftTrailerExtensionContainerSizeEvent.new(hookLiftTrailer, isSmallContainer));
		end;
	end;
end;