local bdlc, c, l = unpack(select(2, ...))

--=======================================
-- StartMockSession
--=======================================
local function rando_name()
	return bdlc.demo_samples.names[math.random(#bdlc.demo_samples.names)]
end
local function rando_ilvl()
	return math.random(900, 980)
end
local function rando_rank()
	return bdlc.demo_samples.ranks[math.random(#bdlc.demo_samples.ranks)]
end
local function rando_class()
	return bdlc.demo_samples.classes[math.random(#bdlc.demo_samples.classes)]
end

bdlc.demo_samples = {
	classes = {"HUNTER","WARLOCK","PRIEST","PALADIN","MAGE","ROGUE","DRUID","WARRIOR","DEATHKNIGHT","MONK","DEMONHUNTER"},
	ranks = {"Officer","Raider","Trial","Social","Alt","Officer Alt","Guild Idiot", "King"},
	names = {"OReilly", "Billy", "Tìncan", "Mango", "Ugh", "Onebutton", "Thor", "Deadpool", "Edgelord", "Yeah", "Arranum", "Witts", "Darkfurion", "Fox", "Cherry"}
}

function bdlc:startMockSession()
	if (IsInRaid() or IsInGroup() or UnitInRaid("player")) then
		if (not bdlc:inLC()) then
			bdlc:print("You cannot run a test while inside of a raid group unless you are on the Loot Council.")
		end
	end

	bdlc:print("Starting mock session")
	
	-- add random people, up to a whole raid worth of fakers
	local demo_players = {}
	for i = 5, math.random(6, 30) do
		demo_players[rando_name()] = {rando_ilvl(), rando_rank(), rando_class()}
	end
	
	-- fake build an LC
	bdlc:sendLC()
	local itemslots = {1, 2, 3, 5, 8, 9, 10, 11, 12, 13, 14, 15}
	bdlc.item_drops = {}
	for i = 1, 4 do
		local index = itemslots[math.random(#itemslots)]
		bdlc.item_drops[GetInventoryItemLink("player", index)] = rando_name()
		table.remove(itemslots,index)
	end

	-- now lets start fake sessions
	for k, v in pairs(bdlc.item_drops) do
		local itemUID = bdlc:GetItemUID(k, bdlc.localPlayer)
		bdlc:sendAction("startSession", k, bdlc.localPlayer);

		-- add our demo players in 
		for name, data in pairs(demo_players) do
			bdlc:sendAction("addUserConsidering", itemUID, name, unpack(data));
		end

		-- send a random "want" after 2-5s, something like a real person
		C_Timer.After(math.random(2, 5), function()
			for name, data in pairs(demo_players) do
				bdlc:sendAction("addUserWant", itemUID, name, math.random(1, 4), 0, 0, math.random(1, 100));
			end
		end)
	end
end

--==========================================
-- Sessions
--==========================================
function bdlc:startSession(itemLink, lootedBy)
	local itemString = string.match(itemLink, "item[%-?%d:]+")
	if (not itemString) then return end
	local itemType, itemID, enchant, gem1, gem2, gem3, gem4, suffixID, uniqueID, level, specializationID, upgradeId, instanceDifficultyID, numBonusIDs, bonusID1, bonusID2, upgradeValue = strsplit(":", itemString)
	
	if (GetItemInfo(itemLink)) then
		local itemUID = bdlc:GetItemUID(itemLink, lootedBy)
		bdlc.itemMap[itemUID] = itemLink
	
		if (bdlc:itemValidForSession(itemLink, lootedBy)) then
			bdlc:debug("Starting session for "..itemLink)
			bdlc.loot_sessions[itemUID] = lootedBy 
			bdlc.loot_want[itemUID] = {}

			if (bdlc:inLC()) then
				bdlc.loot_council_votes[itemUID] = {} 
				bdlc:createVoteWindow(itemUID, lootedBy)
				bdlc:updateVotesRemaining(itemUID, bdlc.localPlayer)
			end

			bdlc:createRollWindow(itemUID, lootedBy)
		end
	else
		bdlc.items_waiting_for_session[itemID] = {itemLink, lootedBy}
		local name = GetItemInfo(itemLink)
	end
end

----------------------------------------
-- EndSession
----------------------------------------
function bdlc:endSession(itemUID)
	local itemLink = bdlc.itemMap[itemUID]

	if not itemLink then return end

	local tab = bdlc:getTab(itemUID)
	tab.entries:ReleaseAll()
	bdlc.tabs:Release(tab)

	local roll = bdlc:getRoll(itemUID)
	bdlc.rolls:Release(roll)

	bdlc.item_drops[itemLink] = nil
	bdlc.loot_sessions[itemUID] = nil
	bdlc.loot_council_votes[itemUID] = nil
	bdlc.loot_want[itemUID] = nil
	
	bdlc:repositionFrames()
end

function bdlc:createVoteWindow(itemUID, lootedBy)
	local itemLink = bdlc.itemMap[itemUID]
	local name, link, quality, iLevel, reqLevel, class, subclass, maxStack, equipSlot, texture, vendorPrice = GetItemInfo(itemLink)
	
	bdlc.window:Show()
	
	-- Set Up tab and item info
	local tab = bdlc:getTab(itemUID)
	tab:Show()
	tab.icon:SetTexture(texture)
	tab.table.item.itemtext:SetText(itemLink)
	tab.table.item.num_items:SetText("Looted by "..bdlc:prettyName(lootedBy, true))
	tab.table.item.num_items:SetTextColor(1,1,1)
	tab.table.item.icon.tex:SetTexture(texture)

	local ilvl, wf_tf, socket, infostr = bdlc:GetItemValue(itemLink)
	tab.wfsock:SetText(infostr)
	tab.table.item.wfsock:SetText(infostr)

	-- bdlc:updateVotesRemaining(itemUID, FetchUnitName('player'))

	local slotname = string.lower(string.gsub(equipSlot, "INVTYPE_", ""));
	slotname = slotname:gsub("^%l", string.upper)
	tab.table.item.itemdetail:SetText("ilvl: "..iLevel.."    "..subclass..", "..slotname);
	tab.table.item:SetScript("OnEnter", function()
		ShowUIPanel(GameTooltip)
		GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
		GameTooltip:SetHyperlink(itemLink)
		GameTooltip:Show()
	end)
	tab.table.item:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	
	
	bdlc:repositionFrames()
end

function bdlc:createRollWindow(itemUID, lootedBy)
	local roll = bdlc.rolls:Acquire()
	local itemLink = bdlc.itemMap[itemUID]
	local name, link, quality, iLevel, reqLevel, class, subclass, maxStack, equipSlot, texture, vendorPrice = GetItemInfo(itemLink)

	roll:Show()
	roll.itemUID = itemUID
	roll.item.icon.tex:SetTexture(texture)
	roll.item.item_text:SetText(itemLink)

	roll.item.num_items:SetText("Looted by "..bdlc:prettyName(lootedBy, true))
	roll.item.num_items:SetTextColor(1,1,1)
	
	-- custom quick notes
	for i = 1, 10 do
		roll.buttons.note.quicknotes[i]:SetText("")
		roll.buttons.note.quicknotes[i]:Hide()
		roll.buttons.note.quicknotes[i]:SetAlpha(0.6)
		roll.buttons.note.quicknotes[i].selected = false
	end

	local ml_qn = {}
	for k, v in pairs(bdlc.master_looter_qn) do
		table.insert(ml_qn, k)
	end
	table.sort(ml_qn)
	for k, v in pairs(ml_qn) do
		local qn
		for i = 1, 10 do
			local rqn = roll.buttons.note.quicknotes[i]
			if (not rqn:IsShown()) then
				qn = rqn
				break
			end
		end
		qn:Show()
		qn:SetText(v)
		bdlc:skinButton(qn,false)
	end

	local ilvl, wf_tf, socket, infostr = bdlc:GetItemValue(itemLink)
	roll.item.icon.wfsock:SetText(infostr)

	roll.item.icon:SetScript("OnEnter", function()
		ShowUIPanel(GameTooltip)
		GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
		GameTooltip:SetHyperlink(itemLink)
		GameTooltip:Show()
	end)
	roll.item.icon:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	
	local guildRank = select(2, GetGuildInfo("player")) or ""
	local player_itemlvl = math.floor(select(2, GetAverageItemLevel()))
	
	if bdlc:itemEquippable(itemUID) then
		bdlc:debug("turns out I can use this, considering.")
		bdlc:sendAction("addUserConsidering", itemUID, bdlc.localPlayer, player_itemlvl, guildRank);
	else
		bdlc:debug("I guess I can't use this, autopassing")
		local itemLink1, itemLink2 = bdlc:fetchUserGear("player", itemLink)
		bdlc.rolls:Release(roll)
	end

	bdlc:repositionFrames()
end

----------------------------------------
-- UpdateUserItem
----------------------------------------
function bdlc:updateUserItem(itemLink, frame)
	local texture = select(10, GetItemInfo(itemLink))
	frame:Show()
	frame.tex:SetTexture(texture)
	frame:SetScript("OnEnter", function()
		ShowUIPanel(GameTooltip)
		GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
		GameTooltip:SetHyperlink(itemLink)
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
end

----------------------------------------
-- AddUserConsidering
----------------------------------------
function bdlc:addUserConsidering(itemUID, playerName, iLvL, guildRank, playerClass)
	local playerName = FetchUnitName(playerName)
	local itemLink = bdlc.itemMap[itemUID]
	
	if not bdlc:inLC() then return false end
	if (not bdlc.loot_sessions[itemUID]) then return false end

	local entry = bdlc:getEntry(itemUID, playerName)

	entry.wantLevel = 15
	entry.notes = ""
	
	local itemName, link, quality, iLevel, reqLevel, class, subclass, maxStack, equipSlot, texture, vendorPrice = GetItemInfo(itemLink)
	local name, server = strsplit("-", playerName)

	local color = bdlc:prettyName(playerName)
	name = GetUnitName(name, true) or name
	
	entry:Show()
	entry.name:SetText(name)
	entry.server = server
	entry.name:SetTextColor(color.r,color.g,color.b);
	entry.interest.text:SetText(l["frameConsidering"]);
	entry.interest.text:SetTextColor(.5,.5,.5);
	entry.rank:SetText(guildRank)
	entry.ilvl:SetText(iLvL)
	entry.gear1:Hide()
	entry.gear2:Hide()
	
	if (IsMasterLooter() or not IsInRaid()) then
		entry.removeUser:Show()
	else
		entry.removeUser:Hide()
	end

	bdlc:repositionFrames()
end

function bdlc:addUserWant(itemUID, playerName, want, itemLink1, itemLink2, roll, notes)
	local playerName = FetchUnitName(playerName)
	if (not notes) then notes = false end
	local itemLink = bdlc.itemMap[itemUID]

	if (not bdlc.loot_sessions[itemUID]) then bdlc:debug(playerName.." rolled on an item with no session") return end
	if (not bdlc:inLC()) then return false end
	
	-- -- actual want text
	local entry = bdlc:getEntry(itemUID, playerName)
	if (not entry) then return end

	bdlc.loot_want[itemUID][playerName] = {itemUID, playerName, want, itemLink1, itemLink2, notes}
	
	local wantText = bdlc.wantTable[want][1]
	local wantColor = bdlc.wantTable[want][2]
	
	bdlc:debug(playerName.." needs "..itemLink.." "..wantText)
	
	entry.interest.text:SetText(wantText)
	entry.interest.text:SetTextColor(unpack(wantColor))
	entry.voteUser:Show()
	entry.wantLevel = want

	-- player items
	if (GetItemInfo(itemLink1)) then
		local itemName, link1, quality, iLevel, reqLevel, class, subclass, maxStack, equipSlot, texture1, vendorPrice = GetItemInfo(itemLink1)
		entry.gear1:Show()
		entry.gear1.tex:SetTexture(texture1)
		entry.gear1:SetScript("OnEnter", function()
			ShowUIPanel(GameTooltip)
			GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
			GameTooltip:SetHyperlink(link1)
			GameTooltip:Show()
		end)
		entry.gear1:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
	else
		local itemID = select(2, strsplit(":", itemLink1))
		if (itemID) then
			bdlc.player_items_waiting[itemID] = {itemLink1, entry.gear1}
		end
	end

	if (GetItemInfo(itemLink2)) then
		local itemName, link1, quality, iLevel, reqLevel, class, subclass, maxStack, equipSlot, texture1, vendorPrice = GetItemInfo(itemLink2)
		entry.gear2:Show()
		entry.gear2.tex:SetTexture(texture1)
		entry.gear2:SetScript("OnEnter", function()
			ShowUIPanel(GameTooltip)
			GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
			GameTooltip:SetHyperlink(link1)
			GameTooltip:Show()
		end)
		entry.gear2:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
	else
		local itemID = select(2, strsplit(":", itemLink2))
		if (itemID) then
			bdlc.player_items_waiting[itemID] = {itemLink2, entry.gear2}
		end
	end
	
	bdlc:repositionFrames()

	-- notes
	bdlc:debug("Add "..playerName.." notes")

	if (notes and string.len(notes) > 0) then
		entry.notes = notes
		entry.user_notes:Show()
	end

	-- roll
	entry.roll = roll
	bdlc:debug(playerName.." rolling on "..itemLink..": "..entry.roll)
end


----------------------------------------
-- RemoveUserConsidering
----------------------------------------
function bdlc:removeUserConsidering(itemUID, playerName)
	if (not bdlc:inLC()) then return end

	-- reset frame
	local tab = bdlc:getTab(itemUID)
	local entry = bdlc:getEntry(itemUID, playerName)

	tab.entries:Release(entry)

	-- stop if no session exists
	if (not bdlc.loot_sessions[itemUID]) then return false end

	-- reset votes
	if (bdlc.loot_council_votes[itemUID]) then
		for council, tab in pairs(bdlc.loot_council_votes[itemUID]) do
			for v = 1, #bdlc.loot_council_votes[itemUID][council] do
				if (bdlc.loot_council_votes[itemUID][council][v] == playerName) then
					bdlc.loot_council_votes[itemUID][council][v] = false
				end
			end
		end

		bdlc:updateVotesRemaining(itemUID, FetchUnitName("player"))
	end

	-- tell that user to kill their roll window
	bdlc.overrideChannel = "WHISPER"
	bdlc.overrideSemder = playerName
	bdlc:sendAction("removeUserRoll", itemUID, playerName);
	bdlc.loot_want[itemUID][playerName] = nil
	
	bdlc:repositionFrames()

	--local itemLink = bdlc.itemMap[itemUID]
	--if (not itemLink) then return end
	
	bdlc:debug("removed "..playerName.." considering "..itemUID)
end

----------------------------------------
-- removeUserRoll
----------------------------------------
function bdlc:removeUserRoll(itemUID, playerName)
	local playerName = FetchUnitName(playerName)
	if (FetchUnitName('player') == playerName) then
		local roll = bdlc:getRoll(itemUID)
		bdlc.rolls:Release(roll)
		bdlc:repositionFrames()
	end
end

----------------------------------------
-- awardLoot
-- This function alerts awarding and then sends a raid message
----------------------------------------
function bdlc:awardLoot(playerName, dropdown, itemUID)
	playerName = FetchUnitName(playerName)
	if (not itemUID) then return end
	local lootedBy = bdlc.loot_sessions[itemUID]
	local itemLink = bdlc.itemMap[itemUID]
	if (not itemLink) then return end

	print(itemLink, lootedBy)

	SendChatMessage("BDLC: "..itemLink.." awarded to "..playerName, "RAID")
	SendChatMessage("BDLC: Please trade "..itemLink.." to "..playerName, "WHISPER", nil, lootedBy)
	-- bdlc:sendAction("addLootHistory", itemUID, playerName)

	dropdown:Hide()
end

----------------------------------------
-- addLootHistory
-- store log of when / what user was awarded in the past
----------------------------------------
-- function bdlc:addLootHistory(itemUID, playerName)

-- end

--==========================================
-- Receive messages
--==========================================
function bdlc:messageCallback(prefix, message, channel, sender)
	local method, partyMaster, raidMaster = GetLootMethod()
	local pre_params = {strsplit(bdlc.deliminator, message)}
	local params = {}
	local action = false

	for k, v in pairs(pre_params) do
		if (v and v ~= "") then
			if (not action) then
				action = v
			else
				if (tonumber(v)) then
					tinsert(params, tonumber(v))
				else
					tinsert(params, v)
				end
			end
		end
	end

	-- -- auto methods have to force a self param
	if (bdlc[action]) then
		if (params and unpack(params)) then -- if params arne't blank
			bdlc[action](self, unpack(params))
		else
			bdlc[action](self)
		end
	else
		bdlc:print("Can't find any function for "..action.." - this usually means you are out of date");
	end
end


----------------------------------------
-- Voting for users
-- supports multiple votes per officer
----------------------------------------
function bdlc:updateVotesRemaining(itemUID, councilName)
	if (councilName ~= FetchUnitName('player')) then return end

	local itemLink = bdlc.itemMap[itemUID]
	local numvotes = 1--bdlc.item_drops[itemLink]
	local currentvotes = 0;
	local color = "|cff00FF00"
	local tab = bdlc:getTab(itemUID)

	if (bdlc.loot_council_votes[itemUID][councilName]) then
		for v = 1, numvotes do
			if (bdlc.loot_council_votes[itemUID][councilName][v]) then
				currentvotes = currentvotes + 1
			end
		end
		
		if (numvotes-currentvotes == 0) then
			color = "|cffFF0000"
		end
	end
	tab.table.numvotes:SetText("Your Votes Remaining: "..color..(numvotes - currentvotes).."|r")

	tab = bdlc:getTab(itemUID)
	for entry, k in tab.entries:EnumerateActive() do
		if (numvotes - currentvotes == 0) then
			if (entry.voteUser:GetText() == l['frameVote']) then
				bdlc:skinButton(entry.voteUser, true, 'dark')
			else
				bdlc:skinButton(entry.voteUser, true, 'blue')
			end
		else
			bdlc:skinButton(entry.voteUser, true, 'blue')
		end
	end
end

function bdlc:voteForUser(councilName, itemUID, playerName, lcl)
	if (not bdlc.loot_sessions[itemUID]) then return false end
	if (not bdlc.loot_council_votes[itemUID]) then return false end
	if not bdlc:inLC() then return false end

	local playerName = FetchUnitName(playerName)

	if (not lcl and FetchUnitName('player') == councilName) then return end
	local itemLink = bdlc.itemMap[itemUID]
	local numvotes = 1 --#bdlc.item_drops[itemLink]
	local votes = bdlc.loot_council_votes[itemUID]

	-- if they haven't voted yet, then give them # votes
	if (not votes[councilName]) then
		print(votes, councilName)
		votes[councilName] = {}
		for v = 1, numvotes do
			votes[councilName][v] = false
		end
	end

	-- only let them vote for each player once
	local hasVotedForPlayer = false
	for v = 1, numvotes do
		if (votes[councilName][v] == playerName) then hasVotedForPlayer = v break end
	end
		
	if (hasVotedForPlayer) then
		votes[councilName][hasVotedForPlayer] = false
		if (FetchUnitName('player') == councilName) then
			local entry = bdlc:getEntry(itemUID, playerName)
			entry.voteUser:SetText(l["frameVote"])
		end
	else
		-- disable rolling votes? limit at # here
		local currentvotes = 0;
		for v = 1, numvotes do
			if (votes[councilName][v]) then
				currentvotes = currentvotes + 1
			end
		end

		if (currentvotes < numvotes) then
			-- reset the table
			local new = {}
			new[1] = false -- reserve pos 1
			for v = 1, numvotes do
				if (votes[councilName][v]) then -- correct any table key gaps
					new[#new+1] = votes[councilName][v]
				end
			end
			votes[councilName] = new -- reset the tables keys

			-- remove the least recent vote
			if (FetchUnitName('player') == councilName) then
				local entry = bdlc:getEntry(itemUID, votes[councilName][numvotes+1])
				entry.voteUser:SetText(l["frameVote"])
			end
			votes[councilName][numvotes+1] = nil 

			votes[councilName][1] = playerName -- prepend the vote
			if (FetchUnitName('player') == councilName) then
				local entry = bdlc:getEntry(itemUID, playerName)
				entry.voteUser:SetText(l["frameVoted"])
			end
		end

	end
	bdlc:updateVotesRemaining(itemUID, councilName)

	-- now loop through and tally
	for itemUID, un in pairs(bdlc.loot_sessions) do
		local tab = bdlc:getTab(itemUID)
		for entry, k in tab.entries:EnumerateActive() do
			if (entry.itemUID) then
				local votes = 0
				for council, v in pairs(bdlc.loot_council_votes[itemUID]) do
					for v = 1, numvotes do
						if bdlc.loot_council_votes[itemUID][council][v] == entry.playerName then
							votes = votes + 1
						end
					end
				end
				entry.votes.text:SetText(votes)
			end

		end
	end
end

--==========================================
-- Async Item Info
--==========================================
bdlc.async = CreateFrame("frame", nil, UIParent)
bdlc.async:RegisterEvent("GET_ITEM_INFO_RECEIVED")
bdlc.async:SetScript("OnEvent", function( event, incomingItemID)
	-- Queue items that need to verify tradability
	for itemID, v in pairs(bdlc.items_waiting_for_verify) do
		local num1 = tonumber(incomingItemID)
		local num2 = tonumber(itemID)
		if (num1 == num2) then
			
			if not bdlc.tradedItems[v] then
			-- TODO: This event can't fire after a trade so this test should be removed?
				if (bdlc:verifyTradability(v)) then
					bdlc:sendAction("startSession", v, FetchUnitName('player'))
				end
			else
				print('Experimental: Item received via trading, will not be announced again.')
			end
			
			bdlc.items_waiting_for_verify[itemID] = nil
		end
	end

	-- Queue items that are starting sessions
	for itemID, v in pairs(bdlc.items_waiting_for_session) do
		local num1 = tonumber(incomingItemID)
		local num2 = tonumber(itemID)
		if (num1 == num2) then
			bdlc:startSession(v[1], v[2])
			bdlc.items_waiting_for_session[itemID] = nil
		end
	end
	
	-- Queue items that are showing user's current gear
	for itemID, v in pairs(bdlc.player_items_waiting) do
		local num1 = tonumber(incomingItemID)
		local num2 = tonumber(itemID)
		if (num1 == num2) then
			bdlc:updateUserItem(v[1], v[2])
			bdlc.player_items_waiting[itemID] = nil
		end
	end
end)