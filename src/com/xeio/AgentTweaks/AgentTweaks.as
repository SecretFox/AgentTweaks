import com.GameInterface.DistributedValue;
import com.GameInterface.DistributedValueBase;
import com.GameInterface.AgentSystemAgent;
import com.GameInterface.AgentSystemMission;
import com.GameInterface.AgentSystem;
import com.GameInterface.Game.Character;
import com.GameInterface.Inventory;
import com.GameInterface.InventoryItem;
import com.Utils.Archive;
import com.Utils.Colors;
import com.Utils.LDBFormat;
import com.xeio.AgentTweaks.Utils;
import gfx.controls.CheckBox;
import mx.utils.Delegate;

class com.xeio.AgentTweaks.AgentTweaks
{    
    private var m_swfRoot: MovieClip;

    private var m_uiScale:DistributedValue;
    
    private var m_timeout:Number;
    
    static var GEAR_BAG:String = LDBFormat.LDBGetText(50200, 9405788);
    static var HEIGHT:Number = 20;
    static var BONUS_OFFSET:Number = 310;
    
    private static var MATCH_NONE = 0;
    private static var MATCH_PARTIAL = 1;
    private static var MATCH_FULL = 2;
    
    static var CHARISMA_ITEM:String = LDBFormat.LDBGetText(50200, 9399665);
    static var POWER_ITEM:String = LDBFormat.LDBGetText(50200, 9399667);
    static var INTELLIGENCE_ITEM:String = LDBFormat.LDBGetText(50200, 9399669);
    static var DEXTERITY_ITEM:String = LDBFormat.LDBGetText(50200, 9399671);
    static var SUPERNATURAL_ITEM:String = LDBFormat.LDBGetText(50200, 9399673);
    static var RESILIENCE_ITEM:String = LDBFormat.LDBGetText(50200, 9399675);
    
    var m_agentInventory:Inventory;
    var m_FavoriteAgents:Array;
    
    static var FAVORITE_PROP:String = "U_FAVORITE";
    static var ARCHIVE_FAVORITES:String = "FavoriteAgents";

    public static function main(swfRoot:MovieClip):Void 
    {
        var AgentTweaks = new AgentTweaks(swfRoot);

        swfRoot.onLoad = function() { AgentTweaks.OnLoad(); };
        swfRoot.OnUnload =  function() { AgentTweaks.OnUnload(); };
        swfRoot.OnModuleActivated = function(config:Archive) { AgentTweaks.Activate(config); };
        swfRoot.OnModuleDeactivated = function() { return AgentTweaks.Deactivate(); };
    }

    public function AgentTweaks(swfRoot: MovieClip) 
    {
        m_swfRoot = swfRoot;
    }

    public function OnUnload()
    {
        AgentSystem.SignalAgentStatusUpdated.Disconnect(AgentStatusUpdated, this);
        AgentSystem.SignalAvailableMissionsUpdated.Disconnect(AvailableMissionsUpdated, this);
        AgentSystem.SignalMissionCompleted.Disconnect(MissionCompleted, this);
        m_uiScale.SignalChanged.Disconnect(SetUIScale, this);        
        m_uiScale = undefined;
        //In the off chance it's just this add-on unloading, close the whole agent system too so our events don't break things
        DistributedValueBase.SetDValue("agentSystem_window", false);
    }
    
    
    public function Activate(config: Archive)
    {
        m_FavoriteAgents = [];
        var favorites:Array = config.FindEntryArray(ARCHIVE_FAVORITES);
        for (var i = 0; i < favorites.length; i++)
        {
            m_FavoriteAgents.push(favorites[i]);
        }
    }

    public function Deactivate(): Archive
    {
        var archive: Archive = new Archive();
        for (var i = 0; i < m_FavoriteAgents.length; i++ )
        {
            archive.AddEntry(ARCHIVE_FAVORITES, m_FavoriteAgents[i]);
        }
        return archive;
    }
	
	public function OnLoad()
	{
        m_uiScale = DistributedValue.Create("AgentTweaks_UIScale");
        m_uiScale.SignalChanged.Connect(SetUIScale, this);
        
        AgentSystem.SignalAgentStatusUpdated.Connect(AgentStatusUpdated, this);
        AgentSystem.SignalAvailableMissionsUpdated.Connect(AvailableMissionsUpdated, this);
        AgentSystem.SignalMissionCompleted.Connect(MissionCompleted, this);
        
        m_agentInventory = new Inventory(new com.Utils.ID32(_global.Enums.InvType.e_Type_GC_AgentEquipmentInventory, Character.GetClientCharID().GetInstance()));
        
        InitializeUI();
	}
    
    private function AgentStatusUpdated(agentData:AgentSystemAgent)
    {
        if (_root.agentsystem.m_Window.m_Content.m_AgentInfoSheet.m_AgentData.m_AgentId == agentData.m_AgentId)
        {
            ScheduleMissionDisplayUpdate();
            UpdateAgentDisplay(agentData);
        }
        setTimeout(Delegate.create(this, HighlightMatchingBonuses), 50);
        ScheduleResort();
    }
    
    private function ResortRoster()
    {
        var roster = _root.agentsystem.m_Window.m_Content.m_Roster;
        if (!roster)
        {
            return;
        }
        
        if (m_FavoriteAgents.length == 0)
        {
            //No favorites, don't need to resort
            return;
        }
        
        for (var i:Number = 0; i < roster.m_AllAgents.length; i++)
        {
            roster.m_AllAgents[i][FAVORITE_PROP] = Utils.Contains(m_FavoriteAgents, roster.m_AllAgents[i].m_AgentId);
            if (roster.m_SortObject.options == 0 && roster.m_CompareMission == undefined)
            {
                //If not sorted by descending, reverse favorited property so these still show at the start
                roster.m_AllAgents[i][FAVORITE_PROP] = !roster.m_AllAgents[i][FAVORITE_PROP];
            }
        }
        
        var ownedAgents = new Array();
        var unownedAgents = new Array();
        for (var i:Number = 0; i < roster.m_AllAgents.length; i++)
        {
            if (AgentSystem.HasAgent(roster.m_AllAgents[i].m_AgentId))
            {
                ownedAgents.push(roster.m_AllAgents[i]);
            }
            else
            {
                unownedAgents.push(roster.m_AllAgents[i]);
            }
        }

        if (roster.m_CompareMission == undefined)
        {
            if (roster.m_SortObject.fields[0] != FAVORITE_PROP)
            {
                roster.m_SortObject.fields.unshift(FAVORITE_PROP);
            }
            ownedAgents.sortOn(roster.m_SortObject.fields, roster.m_SortObject.options);
        }
        else
        {
            ownedAgents.sortOn([FAVORITE_PROP, "m_SuccessChance", "m_Level", "m_Order"], Array.DESCENDING | Array.NUMERIC);
        }
        roster.m_AllAgents = ownedAgents.concat(unownedAgents);
        roster.SetPage(roster.m_CurrentPage);
        
        HighlightMatchingBonuses();
    }
    
    private function MissionCompleted()
    {
        ScheduleMissionDisplayUpdate();
    }
    
    public function SetUIScale()
    {
        _root.agentsystem._xscale = m_uiScale.GetValue();
        _root.agentsystem._yscale = m_uiScale.GetValue();
    }
    
    private function InitializeUI()
    {
        var content = _root.agentsystem.m_Window.m_Content;
        
        if (!content.m_Roster || !content.m_MissionList)
        {
            setTimeout(Delegate.create(this, InitializeUI), 50);
            return;
        }
        
        SetUIScale();
        
        content.m_MissionList.SignalEmptyMissionSelected.Connect(SlotEmptyMissionSelected, this);
        
        content.m_Roster.SignalAgentSelected.Connect(SlotAgentSelected, this);
        
        var inventoryPanel : MovieClip = content.m_InventoryPanel;
        var removeAllButton = inventoryPanel.attachMovie("Final claim Reward States", "u_unequipAll", inventoryPanel.getNextHighestDepth());
        removeAllButton._y -= 15;
        removeAllButton._width = 160
        removeAllButton.textField.text = "Get All Items";
        removeAllButton.disableFocus = true;
        removeAllButton.addEventListener("click", this, "UnequipAll");
		
		var roster = content.m_Roster;
		var hideMaxCB = roster.attachMovie("CheckBoxNoneLabel", "u_hidemaxCB", roster.getNextHighestDepth());
		hideMaxCB.disableFocus = true;
		hideMaxCB._x = roster.m_NextButton._x + 50;
		hideMaxCB._y = roster.m_NextButton._y - 3.5;
		hideMaxCB.addEventListener("click", this, "HideMaxLevelChanged");
		HideMaxLevelChanged();
		
		var hideMaxLabel = roster.createTextField("u_hidemaxText", roster.getNextHighestDepth(), hideMaxCB._x + 12, hideMaxCB._y, 100, 20)
		hideMaxLabel.setNewTextFormat(roster.m_PageNum.getTextFormat());
		hideMaxLabel.embedFonts = true;
		hideMaxLabel.text = "Hide Max Level";
        
        content.m_Roster.m_PrevButton.addEventListener("click", this, "HighlightMatchingBonuses");
        content.m_Roster.m_NextButton.addEventListener("click", this, "HighlightMatchingBonuses");
        content.m_Roster.m_SortDropdown.addEventListener("change", this, "ScheduleResort");
        
        ScheduleResort();
    }
	
	private function HideMaxLevelChanged() 
	{
		var roster = _root.agentsystem.m_Window.m_Content.m_Roster;
		roster.m_FilterObject["maxlevel"] = roster.u_hidemaxCB.selected;
		roster.SetPage(roster.m_CurrentPage);
	}
    
    private function ShowAvailableMissions()
    {
        _root.agentsystem.m_Window.m_Content.m_MissionList.SignalEmptyMissionSelected.Emit();
    }
    
    private function SlotEmptyMissionSelected()
    {
        setTimeout(Delegate.create(this, InitializeAvailableMissionsListUI), 100);
    }
    
    private function InitializeAvailableMissionsListUI()
    {
        var availableMissionList = _root.agentsystem.m_Window.m_Content.m_AvailableMissionList;
        
        if (!availableMissionList)
        {
            setTimeout(Delegate.create(this, InitializeAvailableMissionsListUI), 100);
            return;
        }
        
        if (!availableMissionList.u_customHooksInitialized)
        {
            availableMissionList.u_customHooksInitialized = true;
            
            availableMissionList.m_ButtonBar.addEventListener("change", this, "ScheduleMissionDisplayUpdate");
            
            AgentSystem.SignalAvailableMissionsUpdated.Disconnect(availableMissionList.SlotAvailableMissionsUpdated, availableMissionList);
            
            availableMissionList.SignalMissionSelected.Connect(MissionSelected, this);
        }
        
        ScheduleMissionDisplayUpdate();        
    }
    
    private function ScheduleResort()
    {
        setTimeout(Delegate.create(this, ResortRoster), 40);
    }
    
    private function MissionSelected()
    {
        ScheduleResort();
        InitializeMissionDetailUI();
    }
    
    private function InitializeMissionDetailUI()
    {
        var missionDetail = _root.agentsystem.m_Window.m_Content.m_MissionDetail;
        
        if (!missionDetail)
        {
            setTimeout(Delegate.create(this, InitializeMissionDetailUI), 100);
            return;
        }
        
        missionDetail.SignalClose.Connect(ClearMatches, this);
        missionDetail.SignalClose.Connect(ScheduleResort, this);
        missionDetail.SignalStartMission.Connect(ClearMatches, this);
        missionDetail.SignalStartMission.Connect(ScheduleResort, this);
        
        HighlightMatchingBonuses();
    }
    
    private function AvailableMissionsUpdated(starRating:Number)
	{
        var availableMissionList = _root.agentsystem.m_Window.m_Content.m_AvailableMissionList;
        if (!availableMissionList)
        {
            return;
        }
        
        availableMissionList.SlotAvailableMissionsUpdated(starRating);
        
		if (starRating == 0 || starRating == _root.agentsystem.m_Window.m_Content.m_AvailableMissionList.m_TabIndex + 1)
		{
		    ScheduleMissionDisplayUpdate();
		}
	}
    
    private function ScheduleMissionDisplayUpdate()
    {
        if (!m_timeout)
        {
            //Prevent the UI from updating too often, or our item icon boxes will become invalid
            m_timeout = setTimeout(Delegate.create(this, UpdateMissionsDisplay), 20);
        }
    }
    
    private function UpdateMissionsDisplay()
    {
        m_timeout = undefined;
        
        var availableMissionList = _root.agentsystem.m_Window.m_Content.m_AvailableMissionList;
        
        if (!availableMissionList)
        {
            return;
        }
        
        var agent:AgentSystemAgent = _root.agentsystem.m_Window.m_Content.m_AgentInfoSheet.m_AgentData;
                
        for(var i:Number = 0; i < 5; i++)
        {
            var slotId:String = "m_Slot_" + i;
            var slot:MovieClip = availableMissionList[slotId];
            
            var agentIcon = slot.m_AgentIcon;
            var missionData:AgentSystemMission = slot.m_MissionData;
            var bonusView = slot.m_BonusView;
            
            //Force the teaser reward to be the primary mission reward (this undoes the Funcom change to the base UI)
            missionData.m_TeaserReward = missionData.m_Rewards[0];
            slot.UpdateReward();
            
            if (agent && missionData && missionData.m_MissionId > 0)
            {
                var successChance:Number = AgentSystem.GetSuccessChanceForAgent(agent.m_AgentId, missionData.m_MissionId);
                agentIcon.m_Success._visible = true;
                agentIcon.m_Success.m_Text.text = successChance + "%";
                
                if (BonusIsMatch(agent, missionData))
                {
                    bonusView.m_Header.textColor = 0x00FF00
                }
                else
                {
                    bonusView.m_Header.textColor = 0xFFFFFF
                }
                
                var missionOverride = AgentSystem.GetMissionOverride(missionData.m_MissionId, agent.m_AgentId);
                UpdateRewards(slot, missionData, missionOverride);
                SetMissionSlotTimer(slot, missionData, missionOverride);
            }
            else if(missionData && missionData.m_MissionId > 0)
            {
                UpdateRewards(slot, missionData, missionData);
                SetMissionSlotTimer(slot, missionData, missionData);
                agentIcon.m_Success._visible = false;
                bonusView.m_Header.textColor = 0xFFFFFF
            }
            else
            {
                agentIcon.m_Success._visible = false;
            }
            
            for (var j = 0; j <= 10; j++)
            {
                //Clear any items if they exist
                slot["u_customItems" + j].removeMovieClip();
            }
            
            if (missionData && missionData.m_MissionId > 0)
            {
                if (!slot.u_bonusText)
                {
                    var m_Timer:TextField = slot.m_Timer;
                    var bonusText:TextField = slot.createTextField("u_bonusText", slot.getNextHighestDepth(), 0, slot.m_ActiveBG._height - 15, 100, 20);
                    bonusText.setNewTextFormat(m_Timer.getTextFormat());
                    bonusText.text = "Bonuses";
                    bonusText.embedFonts = true;
                }
                
                var customItemCount = 0;
                var normal = 0;
                var bonus = 0;
                for (var r in missionData.m_Rewards)
                {
                    if (r == 0) continue; //Skip the first reward, since it's going to show in the preview box
                    var item:InventoryItem = Inventory.CreateACGItemFromTemplate(missionData.m_Rewards[r], 0, 0, 1);
                    if(IsImportant(item))
                    {
                        var newItem = slot.attachMovie("IconSlot", "u_customItems" + customItemCount, slot.getNextHighestDepth());
                        newItem._height = newItem._width = HEIGHT;
                        newItem._y = slot.m_ActiveBG._height - newItem._height - 5;
                        newItem._x = 120 + (HEIGHT + 5) * normal;
                        var itemslot = new _global.com.Components.ItemSlot(undefined, 0, newItem);
                        itemslot.SignalMouseUp.Connect(slot.HitAreaReleaseHandler, slot);
                        itemslot.SetData(item);
                        
                        customItemCount++;
                        normal++;
                    }
                }
                for (var r in missionData.m_BonusRewards)
                {
                    var item:InventoryItem = Inventory.CreateACGItemFromTemplate(missionData.m_BonusRewards[r], 0, 0, 1);
                    if(IsImportant(item))
                    {
                        var newItem = slot.attachMovie("IconSlot", "u_customItems" + customItemCount, slot.getNextHighestDepth());
                        newItem._height = newItem._width = HEIGHT;
                        newItem._y = slot.m_ActiveBG._height - HEIGHT - 5;
                        newItem._x = BONUS_OFFSET - (HEIGHT + 5) * bonus;
                        var itemslot = new _global.com.Components.ItemSlot(undefined, 0, newItem);
                        itemslot.SignalMouseUp.Connect(slot.HitAreaReleaseHandler, slot);
                        itemslot.SetData(item);
                        
                        customItemCount++;
                        bonus++;
                    }
                }
                if (bonus > 0)
                {
                    slot.u_bonusText._x = BONUS_OFFSET - (HEIGHT + 5) * bonus - 50;
                    slot.u_bonusText._visible = true;
                }
                else
                {
                    slot.u_bonusText._visible = false;
                }
            }
            else
            {
                slot.u_bonusText._visible = false;
            }
            
            agentIcon._visible = agentIcon.m_Success._visible;
        }
    }
    
    private function SlotAgentSelected()
    {
        ScheduleMissionDisplayUpdate();
        _root.agentsystem.m_Window.m_Content.m_AgentInfoSheet.SignalClose.Connect(ScheduleMissionDisplayUpdate, this);
        UpdateAgentDisplay();
    }
    
    private function SetMissionSlotTimer(slot:MovieClip, missionData:AgentSystemMission, missionOverride:AgentSystemMission)
    {
        slot.m_Duration.text = slot.CalculateTimeString(missionOverride.m_ActiveDuration, false);
        
        if (missionOverride.m_ActiveDuration < missionData.m_ActiveDuration)
        {
            slot.m_Duration.textColor = Colors.e_ColorPureGreen;
        }
        else if (missionOverride.m_ActiveDuration < missionData.m_ActiveDuration)
        {
            slot.m_Duration.textColor = Colors.e_ColorLightRed;
        }
        else
        {
            slot.m_Duration.textColor = Colors.e_ColorWhite;
        }
    }
    
    private function UpdateAgentDisplay(agent:AgentSystemAgent)
    {
        var agentInfoSheet :MovieClip = _root.agentsystem.m_Window.m_Content.m_AgentInfoSheet;
        if (!agentInfoSheet)
        {
            return;
        }
        
        if (!agent)
        {
            agent = agentInfoSheet.m_AgentData;
        }
        
        var healthField:TextField = agentInfoSheet.u_health;
        if (!healthField)
        {
            var m_Timer : TextField = agentInfoSheet.m_Timer;
            healthField = agentInfoSheet.createTextField("u_health", agentInfoSheet.getNextHighestDepth(), m_Timer._x, m_Timer._y, m_Timer._width, m_Timer._height)
            healthField.setNewTextFormat(m_Timer.getTextFormat())
            healthField.embedFonts = true;
        }
        
        var favoriteField:MovieClip = agentInfoSheet.u_favorite;
        if (!favoriteField)
        {
            var m_Timer : TextField = agentInfoSheet.m_Timer;
            var favoriteText = agentInfoSheet.createTextField("u_favoriteText", agentInfoSheet.getNextHighestDepth(), healthField._x + 80, healthField._y - healthField._height + 3, 50, healthField._height)
            favoriteText.setNewTextFormat(m_Timer.getTextFormat())
            favoriteText.embedFonts = true;
            favoriteText.text = "Favorite";
            
            favoriteField = agentInfoSheet.attachMovie("CheckBoxNoneLabel", "u_favorite", agentInfoSheet.getNextHighestDepth());
            favoriteField.disableFocus = true;
            favoriteField._x = favoriteText._x - 15;
            favoriteField._y = favoriteText._y;
            favoriteField.addEventListener("click", this, "AgentFavoriteChanged");
            
        }
        favoriteField.selected = Utils.Contains(m_FavoriteAgents, agent.m_AgentId);
        
        if (!AgentSystem.IsAgentFatigued(agent.m_AgentId))
        {
            healthField._visible = true;
            healthField.text = "Fatigue: " + (100 - agent.m_FatiguePercent) + "%";
        }
        else
        {
            healthField._visible = false;
        }
    }
    
    private function AgentFavoriteChanged()
    {
        var agentInfoSheet :MovieClip = _root.agentsystem.m_Window.m_Content.m_AgentInfoSheet;
        if (!agentInfoSheet)
        {
            return;
        }
        
        var agent:AgentSystemAgent = agentInfoSheet.m_AgentData;
        if (agentInfoSheet.u_favorite.selected)
        {
            m_FavoriteAgents.push(agent.m_AgentId);
        }
        else
        {
            Utils.Remove(m_FavoriteAgents, agent.m_AgentId);
        }
        
        ScheduleResort();
    }
    
    private function UnequipAll()
    {
        var agents = AgentSystem.GetAgents();
        for (var i in agents)
        {
            var agent:AgentSystemAgent = agents[i];
            if (!AgentSystem.IsAgentOnMission(agent.m_AgentId))
            {
                if(AgentSystem.GetItemOnAgent(agent.m_AgentId).m_Name)
                {
                    var firstFree:Number = m_agentInventory.GetFirstFreeItemSlot();
                    if (firstFree != -1)
                    {
                        AgentSystem.UnequipItemOnAgent(agent.m_AgentId, m_agentInventory.GetInventoryID(), firstFree);
                        setTimeout(Delegate.create(this, UnequipAll), 200)
                        return;
                    }
                    else 
                    {
                        break;
                    }
                }
            }
        }
    }
    
    private function BonusIsMatch(agent:AgentSystemAgent, mission:AgentSystemMission) : Boolean
    {
        if (!mission.m_BonusTraitCategories || mission.m_BonusTraitCategories.length == 0)
        {
            return false;
        }
        
        for (var i in mission.m_BonusTraitCategories)
        {
            var bonusTrait = mission.m_BonusTraitCategories[i];
            if(!AgentHasTrait(agent, bonusTrait))
            {
                return false;
            }
        }
        
        return true;
    }
    
    private function IsImportant(item:InventoryItem)
    {
        if (item.m_Name.indexOf("stillat") != -1 && (item.m_Name.indexOf("cc)") != -1 || item.m_Name.indexOf("cm3)") != -1))
        {
            //Distillates
            return false;
        }
        if (item.m_Name.indexOf("Anima Shards") != -1 || item.m_Name.indexOf("Anima-Splitter") != -1 || item.m_Name.indexOf("Anima-Splitter") != -1)
        {
            //Anima shards
            return false;
        }
        
        //Any uncategorized items are important (known items like Dossiers and Gear bags)
        return true;
    }
    
    private function UpdateRewards(slot:MovieClip, mission:AgentSystemMission, missionOverride:AgentSystemMission)
    {
        var currencyFields = slot.m_Currency;
        
        var originalIntel = mission.m_IntelReward - mission.m_IntelCost;
        var intel = missionOverride.m_IntelReward - missionOverride.m_IntelCost;
        currencyFields.m_Intel.text = (intel > 0 ? "+" : "") + intel;
        if (originalIntel < intel)
        {
            currencyFields.m_Intel.textColor = Colors.e_ColorLightGreen;
        }
        else if (originalIntel > intel)
        {
            currencyFields.m_Intel.textColor = Colors.e_ColorPureRed;
        }
        else
        {
            currencyFields.m_Intel.textColor = Colors.e_ColorWhite;
        }
        
        var originalSupplies = mission.m_SuppliesReward - mission.m_SuppliesCost;
        var supplies = missionOverride.m_SuppliesReward - missionOverride.m_SuppliesCost;
        currencyFields.m_Supplies.text = (supplies > 0 ? "+" : "") + supplies;
        if (originalSupplies < supplies)
        {
            currencyFields.m_Supplies.textColor = Colors.e_ColorLightGreen;
        }
        else if (originalSupplies > supplies)
        {
            currencyFields.m_Supplies.textColor = Colors.e_ColorPureRed;
        }
        else
        {
            currencyFields.m_Supplies.textColor = Colors.e_ColorWhite;
        }
        
        var originalAssets = mission.m_AssetsReward - mission.m_AssetsCost;
        var assets = missionOverride.m_AssetsReward - missionOverride.m_AssetsCost;
        currencyFields.m_Assets.text = (assets > 0 ? "+" : "") + assets;
        if (originalAssets < assets)
        {
            currencyFields.m_Assets.textColor = Colors.e_ColorLightGreen;
        }
        else if (originalAssets > assets)
        {
            currencyFields.m_Assets.textColor = Colors.e_ColorPureRed;
        }
        else
        {
            currencyFields.m_Assets.textColor = Colors.e_ColorWhite;
        }
        
        currencyFields.m_XP.text = missionOverride.m_XPReward;
        if (missionOverride.m_XPReward > mission.m_XPReward)
        {
            currencyFields.m_XP.textColor = Colors.e_ColorLightGreen;
        }
        else
        {
            currencyFields.m_XP.textColor = Colors.e_ColorWhite;
        }
    }
    
    private function ClearMatches()
    {
        var roster = _root.agentsystem.m_Window.m_Content.m_Roster;
        for (var i = 1; i <= 16; i++)
        {
            var rosterIcon = roster["Icon_" + i];
            var agent:AgentSystemAgent = rosterIcon.data;
            var traitPanel = rosterIcon.m_TraitCategories;
            
            for (var t = 0; t < 6; t++)
            {
                traitPanel["u_traitbox" + t].removeMovieClip();
            }
			rosterIcon.m_Frame["u_bonuses"].removeMovieClip();
        }
    }
    
    private function HighlightMatchingBonuses()
    {
        var missionDetail = _root.agentsystem.m_Window.m_Content.m_MissionDetail;
        var mission = missionDetail.m_MissionData;
        
        if (!mission)
        {
            return;
        }        
        
        ClearMatches();
        
        var roster = _root.agentsystem.m_Window.m_Content.m_Roster;
        for (var i = 1; i <= 16; i++)
        {
            var rosterIcon = roster["Icon_" + i];
            var agent:AgentSystemAgent = rosterIcon.data;
            var traitPanel = rosterIcon.m_TraitCategories;
			
			//Do it before match checking because some agents have bonuses even without matches.
			DrawMissionBonus(mission, agent, rosterIcon);
            
            var matchStatus = GetTraitMatchStatus(mission, agent);
            if (matchStatus == MATCH_NONE)
            {
                continue;
            }
            //Otherwise partial or full match
            
            for (var t in mission.m_BonusTraitCategories)
            {
                var bonusTrait = mission.m_BonusTraitCategories[t];
                
                if (AgentHasTrait(agent, bonusTrait))
                {
                    var color = matchStatus == MATCH_FULL ? Colors.e_ColorPureGreen : Colors.e_ColorPureYellow;
                    DrawBoxAroundTrait(traitPanel, TraitToIndex(bonusTrait), color);
                }
                else
                {
                    DrawBoxAroundTrait(traitPanel, TraitToIndex(bonusTrait), Colors.e_ColorPureRed);
                }
            }
        }
    }
	
	private function DrawMissionBonus(mission:AgentSystemMission, agent:AgentSystemAgent, icon:Object) 
	{
		var bonuses:Array = [];
		var missionOverride:AgentSystemMission = AgentSystem.GetMissionOverride(mission.m_MissionId, agent.m_AgentId);
		
		//cost bonuses
		if (missionOverride.m_IntelCost < mission.m_IntelCost)
			bonuses.push(["- intel cost", Colors.e_ColorPureRed]);
		else if (missionOverride.m_IntelCost > mission.m_IntelCost)
			bonuses.push(["+ intel cost", Colors.e_ColorLightRed]);
		
		if (missionOverride.m_SuppliesCost < mission.m_SuppliesCost)
			bonuses.push(["- supplies cost", Colors.e_ColorPureRed]);
		else if (missionOverride.m_SuppliesCost > mission.m_SuppliesCost)
			bonuses.push(["+ supplies cost", Colors.e_ColorLightRed]);
			
		if (missionOverride.m_AssetsCost < mission.m_AssetsCost)
			bonuses.push(["- assets cost", Colors.e_ColorPureRed]);
		else if (missionOverride.m_AssetsCost > mission.m_AssetsCost)
			bonuses.push(["+ assets cost", Colors.e_ColorLightRed]);
		
		//Rewards bonuses
		if (missionOverride.m_IntelReward < mission.m_IntelReward)
			bonuses.push(["- intel reward", Colors.e_ColorLightGreen]);
		else if (missionOverride.m_IntelReward > mission.m_IntelReward)
			bonuses.push(["+ intel reward", Colors.e_ColorPureGreen]);
		
		if (missionOverride.m_SuppliesReward < mission.m_SuppliesReward)
			bonuses.push(["- supplies reward", Colors.e_ColorLightGreen]);
		else if (missionOverride.m_SuppliesReward > mission.m_SuppliesReward)
			bonuses.push(["+ supplies reward", Colors.e_ColorPureGreen]);
			
		if (missionOverride.m_AssetsReward < mission.m_AssetsReward)
			bonuses.push(["- assets reward", Colors.e_ColorLightGreen]);
		else if (missionOverride.m_AssetsReward > mission.m_AssetsReward)
			bonuses.push(["+ assets reward", Colors.e_ColorPureGreen]);
		
		if (bonuses.length)
		{
			var portrait = icon.m_Frame;
			var clip:MovieClip = portrait.createEmptyMovieClip("u_bonuses", portrait.getNextHighestDepth());
			var clipWidth:Number = 104;
			var clipHeight:Number = bonuses.length * 12 + 1;
			var offsetBGTop:Number = 2; //offsetting background makes it look a bit better.
			clip._x = 24;
			clip._y = portrait._height - clipHeight;
			clip.beginFill(0x000000, 50);
			clip.moveTo(0, offsetBGTop); 
			clip.lineTo(clipWidth, offsetBGTop);
			clip.lineTo(clipWidth, clipHeight + offsetBGTop);
			clip.lineTo(0, clipHeight + offsetBGTop);
			clip.lineTo(0, offsetBGTop);
			clip.endFill();
			var y = 0;
			var textFormat:TextFormat = icon.m_Name.getTextFormat();
			textFormat.align = "left";
			textFormat.size = 12;
			textFormat.bold = true;
			for (var i = 0; i < bonuses.length; i++)
			{
				var textfield:TextField = clip.createTextField("m_bonus" + i, clip.getNextHighestDepth(), 0, y, 104, 20);
				textFormat.color = bonuses[i][1];
				textfield.setNewTextFormat(textFormat);
				textfield.embedFonts = true;
				textfield.text = bonuses[i][0];
				
				y += 12;
			}
		}
	}
    
    private function DrawBoxAroundTrait(traitPanel:MovieClip, boxIndex: Number, color:Number)
    {
        var overlay = traitPanel.createEmptyMovieClip("u_traitbox" + boxIndex, traitPanel.getNextHighestDepth());
        var X_OFFSET = -2.5;
        var Y_OFFSET = -4 + boxIndex;
        var HEIGHT = 17.9;
        var WIDTH = 19;
        overlay.lineStyle(2, color);
        overlay.moveTo(X_OFFSET,         Y_OFFSET + HEIGHT * boxIndex);
        overlay.lineTo(X_OFFSET + WIDTH, Y_OFFSET + HEIGHT * boxIndex);
        overlay.lineTo(X_OFFSET + WIDTH, Y_OFFSET + HEIGHT + HEIGHT * boxIndex);
        overlay.lineTo(X_OFFSET,         Y_OFFSET + HEIGHT + HEIGHT * boxIndex);
        overlay.lineTo(X_OFFSET,         Y_OFFSET + HEIGHT * boxIndex);
    }
    
    private function GetTraitMatchStatus(mission:AgentSystemMission, agent:AgentSystemAgent) : Number
    {
        if (!mission.m_BonusTraitCategories || mission.m_BonusTraitCategories.length == 0)
        {
            return MATCH_NONE;
        }
        
        var matchedTraits:Number = 0;
        var missingTrait:Number = 0;
        for (var i in mission.m_BonusTraitCategories)
        {
            var bonusTrait = mission.m_BonusTraitCategories[i];
            if (AgentHasTrait(agent, bonusTrait))
            {
                matchedTraits++;
            }
            else
            {
                missingTrait = bonusTrait;
            }
        }
        
        if (matchedTraits == mission.m_BonusTraitCategories.length)
        {
            return MATCH_FULL;
        }
        if (mission.m_BonusTraitCategories.length > 1 && matchedTraits == mission.m_BonusTraitCategories.length - 1)
        {
            if (HasTraitItem(missingTrait))
            {
                return MATCH_PARTIAL;
            }
        }
        return MATCH_NONE;
    }
    
    private function AgentHasTrait(agent:AgentSystemAgent, trait:Number) :Boolean
    {
        var agentOverrides = AgentSystem.GetAgentOverride(agent.m_AgentId);
        return trait == agent.m_Trait1Category || trait == agent.m_Trait2Category || trait == agentOverrides[3];
    }
    
    private function TraitToIndex(bonusTrait:Number) : Number
    {
        if (bonusTrait == _global.GUI.AgentSystem.SettingsPanel.TRAIT_CAT_POWER) return 0;
        if (bonusTrait == _global.GUI.AgentSystem.SettingsPanel.TRAIT_CAT_RESILIENCE) return 1;
        if (bonusTrait == _global.GUI.AgentSystem.SettingsPanel.TRAIT_CAT_CHARISMA) return 2;
        if (bonusTrait == _global.GUI.AgentSystem.SettingsPanel.TRAIT_CAT_DEXTERITY) return 3;
        if (bonusTrait == _global.GUI.AgentSystem.SettingsPanel.TRAIT_CAT_SUPERNATURAL) return 4;
        if (bonusTrait == _global.GUI.AgentSystem.SettingsPanel.TRAIT_CAT_INTELLIGENCE) return 5;
        return 0;
    }
    
    private function HasTraitItem(bonusTrait:Number)
    {
        var itemName:String = "NOITEM";
        
        if (bonusTrait == _global.GUI.AgentSystem.SettingsPanel.TRAIT_CAT_POWER) itemName = POWER_ITEM;
        if (bonusTrait == _global.GUI.AgentSystem.SettingsPanel.TRAIT_CAT_RESILIENCE) itemName = RESILIENCE_ITEM;
        if (bonusTrait == _global.GUI.AgentSystem.SettingsPanel.TRAIT_CAT_CHARISMA) itemName = CHARISMA_ITEM;
        if (bonusTrait == _global.GUI.AgentSystem.SettingsPanel.TRAIT_CAT_DEXTERITY) itemName = DEXTERITY_ITEM;
        if (bonusTrait == _global.GUI.AgentSystem.SettingsPanel.TRAIT_CAT_SUPERNATURAL) itemName = SUPERNATURAL_ITEM;
        if (bonusTrait == _global.GUI.AgentSystem.SettingsPanel.TRAIT_CAT_INTELLIGENCE) itemName = INTELLIGENCE_ITEM;
        
        for (var i = 0; i < m_agentInventory.GetMaxItems(); i++)
        {
            var item:InventoryItem = m_agentInventory.GetItemAt(i);
            if (item && item.m_Name == itemName)
            {
                return true;
            }
        }
    }
}