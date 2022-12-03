import com.GameInterface.DistributedValue;
import com.GameInterface.DistributedValueBase;
import com.GameInterface.AgentSystemAgent;
import com.GameInterface.AgentSystemMission;
import com.GameInterface.AgentSystem;
import com.GameInterface.Game.Character;
import com.GameInterface.Inventory;
import com.GameInterface.InventoryItem;
import com.GameInterface.Tooltip.TooltipData;
import com.GameInterface.Tooltip.TooltipInterface;
import com.GameInterface.Tooltip.TooltipManager;
import com.Utils.Archive;
import com.Utils.Colors;
import com.Utils.Draw;
import com.Utils.LDBFormat;
import com.xeio.AgentTweaks.Utils;
import mx.utils.Delegate;

class com.xeio.AgentTweaks.AgentTweaks
{
    private var m_swfRoot: MovieClip;

    private var m_uiScale:DistributedValue;
    private var m_fontScale:DistributedValue;

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
    static var Tooltip:TooltipInterface;
    static var SavedAgents:Array;

    static var OutstandingData:Array; // format : OutstandingData[CATEGORYID] = array of matching traits;

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
        Tooltip.Close();
        AgentSystem.SignalAgentStatusUpdated.Disconnect(AgentStatusUpdated, this);
        AgentSystem.SignalActiveMissionsUpdated.Disconnect(UpdateCompleteButton, this);
        AgentSystem.SignalAvailableMissionsUpdated.Disconnect(AvailableMissionsUpdated, this);
        AgentSystem.SignalMissionCompleted.Disconnect(MissionCompleted, this);
        m_uiScale.SignalChanged.Disconnect(SetUIScale, this);
        m_uiScale = undefined;
        m_fontScale.SignalChanged.Disconnect(SetFontScale, this);
        m_fontScale = undefined;
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
        SavedAgents = [];
        var pairs = string(config.FindEntry("SavedAgentsAgents", [])).split("|");
        for ( var i in pairs) 
        {
            SavedAgents.push(pairs[i].split("&"));
            //com.GameInterface.UtilsBase.PrintChatText("MissionId " + pairs[i].split("&")[0] + " agentId " + pairs[i].split("&")[1]);
        }
    }

    public function Deactivate(): Archive
    {
        var archive: Archive = new Archive();
        for (var i = 0; i < m_FavoriteAgents.length; i++ )
        {
            archive.AddEntry(ARCHIVE_FAVORITES, m_FavoriteAgents[i]);
        }
        var Saved = [];
        for (var i in SavedAgents) Saved[i] = SavedAgents[i].join("&")
        Saved = Saved.join("|");
        archive.AddEntry("SavedAgentsAgents", Saved);
        return archive;
    }

    public function OnLoad()
    {
        m_uiScale = DistributedValue.Create("AgentTweaks_UIScale");
        m_uiScale.SignalChanged.Connect(SetUIScale, this);
        m_fontScale = DistributedValue.Create("AgentTweaks_FontScale");
        m_fontScale.SignalChanged.Connect(SetFontScale, this);

        AgentSystem.SignalAgentStatusUpdated.Connect(AgentStatusUpdated, this);
        AgentSystem.SignalAvailableMissionsUpdated.Connect(AvailableMissionsUpdated, this);
        AgentSystem.SignalMissionCompleted.Connect(MissionCompleted, this);
        AgentSystem.SignalActiveMissionsUpdated.Connect(UpdateCompleteButton, this);

        m_agentInventory = new Inventory(new com.Utils.ID32(_global.Enums.InvType.e_Type_GC_AgentEquipmentInventory, Character.GetClientCharID().GetInstance()));

        OutstandingData = new Array(7);

        OutstandingData[0]   = [163];        //Blajini Crit Chance
        OutstandingData[121] = [553];         //Power
        OutstandingData[122] = [531, 555];     //Resilience
        OutstandingData[118] = [541, 2678]; //Charisma
        OutstandingData[119] = [176, 2671]; //Dexterity
        OutstandingData[123] = [243];         //Supernatural
        OutstandingData[120] = [205, 536];     //Intelligence

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

    public function SetFontScale()
    {
        var scale:Number = m_fontScale.GetValue();
        for (var i = 0; i < 5; i++)
        {
            var activeSlot = _root.agentsystem.m_Window.m_Content.m_MissionList["m_Slot_" + i];
            var availableSlot = _root.agentsystem.m_Window.m_Content.m_AvailableMissionList["m_Slot_" + i];

            //Active Timer
            var activeTimer = activeSlot.m_ActiveBG.m_Progress.m_Timer;
            var baseY = activeTimer._y * 100.0 / activeTimer._yscale; //Simple scaling works fine here
            activeTimer._y = baseY / 100.0 * scale;

            var baseWidth = activeTimer._width / (activeTimer._xscale / 100.0);
            var baseX = activeTimer._x + baseWidth * (activeTimer._xscale / 100.0 - 1.0);
            activeTimer._x = baseX - baseWidth * (scale / 100.0 - 1.0);

            activeTimer._xscale = scale;
            activeTimer._yscale = scale;
        }

        ScaleAvailableMissions();
    }

    private function ScaleAvailableMissions()
    {
        var availableMissions = _root.agentsystem.m_Window.m_Content.m_AvailableMissionList;

        if (!availableMissions)
            return;

        var scale:Number = m_fontScale.GetValue();
        for (var i = 0; i < 5; i++)
        {
            var availableSlot = availableMissions["m_Slot_" + i];

            //Currencies
            SetTextfieldScale(availableSlot.m_Currency.m_Intel, scale);
            SetTextfieldScale(availableSlot.m_Currency.m_Supplies, scale);
            SetTextfieldScale(availableSlot.m_Currency.m_Assets, scale);
            SetTextfieldScale(availableSlot.m_Currency.m_XP, scale);

            //Duration
            var duration = availableSlot.m_Duration;
            var baseHeight = duration._height / (duration._yscale / 100.0);
            var baseY = duration._y + baseHeight * (duration._yscale / 100.0 - 1.0) / 10.0;
            duration._y = baseY - baseHeight * (scale / 100.0 - 1.0) / 10.0;

            var baseWidth = duration._width / (duration._xscale / 100.0);
            var baseX = duration._x + baseWidth * (duration._xscale / 100.0 - 1.0) / 2.0;
            duration._x = baseX - baseWidth * (scale / 100.0 - 1.0) / 2.0;

            duration._xscale = scale;
            duration._yscale = scale;
        }
    }

    private function SetTextfieldScale(field:TextField, scale:Number)
    {
        var baseHeight = field._height / (field._yscale / 100.0);
        var baseY = field._y + baseHeight * (field._yscale / 100.0 - 1.0) / 2.0;
        field._y = baseY - baseHeight * (scale / 100.0 - 1.0) / 2.0;

        field._xscale = scale;
        field._yscale = scale;
    }

    public function SetBonusesIcons()
    {
        HighlightMatchingBonuses();
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
        SetFontScale();

        content.m_MissionList.SignalEmptyMissionSelected.Connect(SlotEmptyMissionSelected, this);

        content.m_Roster.SignalAgentSelected.Connect(SlotAgentSelected, this);

        var inventoryPanel : MovieClip = content.m_InventoryPanel;
        var removeAllButton = inventoryPanel.attachMovie("Final claim Reward States", "u_unequipAll", inventoryPanel.getNextHighestDepth());
        removeAllButton._y -= 15;
        removeAllButton._width = 160;
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

        var hideMaxLabel = roster.createTextField("u_hidemaxText", roster.getNextHighestDepth(), hideMaxCB._x + 12, hideMaxCB._y, 100, 20);
        hideMaxLabel.setNewTextFormat(roster.m_PageNum.getTextFormat());
        hideMaxLabel.embedFonts = true;
        hideMaxLabel.text = "Hide Max Level";

        var missionPanel : MovieClip = content.m_MissionList;
        var acceptAllMissionsButton = missionPanel.attachMovie("Final claim Reward States", "u_acceptAll", missionPanel.getNextHighestDepth());
        acceptAllMissionsButton._y = missionPanel.m_ViewMissionsButton._y + missionPanel.m_ViewMissionsButton._height;
        acceptAllMissionsButton._x = missionPanel.m_ViewMissionsButton._x;
        acceptAllMissionsButton._width = missionPanel.m_ViewMissionsButton._width;
        acceptAllMissionsButton.textField.text = "Accept All Rewards";
        acceptAllMissionsButton.disableFocus = true;
        acceptAllMissionsButton.addEventListener("click", this, "AcceptMissionRewards");
        UpdateCompleteButton();

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
        HighlightMatchingBonuses();
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
    
    private function LoadSaved(event:Object)
    {
        if ( AgentSystem.HasAgent(event["target"]["agent"]))
        {
            _root.agentsystem.m_Window.m_Content.m_Roster.SignalAgentSelected.Emit(AgentSystem.GetAgentById(event["target"]["agent"]));
        }
    }
    
    private function SetSaved()
    {
        var missionDetail = _root.agentsystem.m_Window.m_Content.m_MissionDetail;
        if (missionDetail)
        {
            var agent:AgentSystemAgent = missionDetail.m_AgentData;
            var mission:AgentSystemMission = missionDetail.m_MissionData
            if (AgentSystem.HasAgent(agent.m_AgentId) && mission)
            {
                var found;
                for (var i in SavedAgents)
                {
                    if ( SavedAgents[i][0] == mission.m_MissionId)
                    {
                        SavedAgents[i][1] = agent.m_AgentId;
                        found = true;
                        break;
                    }
                }
                if (!found) SavedAgents.push([mission.m_MissionId, agent.m_AgentId]);
            }
        }
    }
    
    private function CreateSaveButton(missionDetail:MovieClip)
    {
        missionDetail.m_SaveButton.setMask(null);
        missionDetail.saveMask.removeMovieClip();
        missionDetail.m_SaveButton.removeMovieClip();
        var m_SaveButton:MovieClip = missionDetail.m_DeployButton.duplicateMovieClip(
            "m_SaveButton", 
            missionDetail.getNextHighestDepth(),
            {_x:-25, _y:missionDetail.m_DeployButton._y - missionDetail.m_DeployButton._height/2}
        );
        m_SaveButton.textField._x = 55;
        TextField(m_SaveButton.textField).autoSize = true;
        m_SaveButton._width = 150;
        m_SaveButton.label = "Save";
        m_SaveButton.addEventListener("click", this, "SetSaved");
        
        m_SaveButton.setMask(null);        
        var mask:MovieClip = missionDetail.createEmptyMovieClip("saveMask", missionDetail.getNextHighestDepth());
        mask._x = m_SaveButton._x;
        mask._y = m_SaveButton._y;
        mask.beginFill(0xFF0000);
        mask.moveTo(28, 0);
        mask.lineTo(120, 0);
        mask.lineTo(120, m_SaveButton._height);
        mask.lineTo(28, m_SaveButton._height);
        mask.lineTo(28, 0);
        mask.endFill();
        m_SaveButton.setMask(mask);
    }
    
    private function CreateLoadButton(missionDetail:MovieClip, agentID:Number)
    {
        if (AgentSystem.HasAgent(agentID))
        {
            missionDetail.m_LastAgent.setMask(null);
            missionDetail.lastMask.removeMovieClip();
            var m_LastAgent:MovieClip = missionDetail.m_DeployButton.duplicateMovieClip(
                "m_LastAgent", 
                missionDetail.getNextHighestDepth(),
                {_x:-25, _y:missionDetail.m_DeployButton._y + missionDetail.m_DeployButton._height/2}
            );
            m_LastAgent.textField._x = 55;
            TextField(m_LastAgent.textField).autoSize = true;
            m_LastAgent._width = 150;
            m_LastAgent.label = "Load";
            m_LastAgent.agent = agentID;
            m_LastAgent.addEventListener("click", this, "LoadSaved");

            var mask:MovieClip = missionDetail.createEmptyMovieClip("lastMask", missionDetail.getNextHighestDepth());
            mask._x = m_LastAgent._x;
            mask._y = m_LastAgent._y;
            mask.beginFill(0xFF0000);
            mask.moveTo(28, 0);
            mask.lineTo(120, 0);
            mask.lineTo(120, m_LastAgent._height);
            mask.lineTo(28, m_LastAgent._height);
            mask.lineTo(28, 0);
            mask.endFill();
            m_LastAgent.setMask(mask);
        }
    }

    private function InitializeMissionDetailUI()
    {
        var missionDetail:MovieClip = _root.agentsystem.m_Window.m_Content.m_MissionDetail;

        if (!missionDetail)
        {
            setTimeout(Delegate.create(this, InitializeMissionDetailUI), 100);
            return;
        };
        var agentInfoSheet = _root.agentsystem.m_Window.m_Content.m_AgentInfoSheet;
        agentInfoSheet.m_HitBox.removeMovieClip();
        missionDetail.m_HitBox.removeMovieClip();
        var missionData:AgentSystemMission = missionDetail.m_MissionData;
        var agent:AgentSystemAgent = agentInfoSheet.m_AgentData;
        var found:Boolean;
        for (var i in SavedAgents)
        {
            if (SavedAgents[i][0] == missionData.m_MissionId)
            {
                found = true;
                CreateLoadButton(missionDetail, SavedAgents[i][1]);
                break;
            }
        }
        CreateSaveButton(missionDetail);

        if ( agentInfoSheet )
        {
            if (AgentSystem.HasAgent(agent.m_AgentId))
            {
                var successChance:Number = AgentSystem.GetSuccessChanceForAgent(agent.m_AgentId, missionData.m_MissionId);
                var crit:Object = CalculateCrit(missionData, agent, successChance);
                if ( crit["val"] || crit["text"])
                {
                    setTimeout(Delegate.create(this, function()
                    {
                        var content:String = crit["val"] ? crit["val"][0] + " + " + crit["val"][1] : crit["text"];
                        agentInfoSheet.m_AgentIcon.m_Success.m_Text.multiline = true;
                        agentInfoSheet.m_AgentIcon.m_Success.m_Text.autoSize = "center";
                        agentInfoSheet.m_AgentIcon.m_Success.m_Text.htmlText = 
                            "<TEXTFORMAT INDENT=\"0\" LEFTMARGIN=\"0\" RIGHTMARGIN=\"0\" LEADING=\"2\"><P ALIGN=\"CENTER\"><FONT FACE=\"Futura Std Book Fix\" SIZE=\"37\" COLOR=\"#CCCCCC\" KERNING=\"0\">" +
                            successChance + "%</FONT></P></TEXTFORMAT>" +
                            "<TEXTFORMAT INDENT=\"0\" LEFTMARGIN=\"0\" RIGHTMARGIN=\"0\" LEADING=\"2\"><P ALIGN=\"CENTER\"><FONT FACE=\"Futura Std Book Fix\" SIZE=\"15\" COLOR=\"#CCCCCC\" KERNING=\"0\">" +
                            content + "</FONT></P></TEXTFORMAT>";
                        missionDetail.m_Agent.m_Success.m_Text.multiline = true;
                        missionDetail.m_Agent.m_Success.m_Text.autoSize = "center";
                            "<TEXTFORMAT INDENT=\"0\" LEFTMARGIN=\"0\" RIGHTMARGIN=\"0\" LEADING=\"2\"><P ALIGN=\"CENTER\"><FONT FACE=\"Futura Std Book Fix\" SIZE=\"37\" COLOR=\"#CCCCCC\" KERNING=\"0\">" +
                            successChance + "%</FONT></P></TEXTFORMAT>" +
                            "<TEXTFORMAT INDENT=\"0\" LEFTMARGIN=\"0\" RIGHTMARGIN=\"0\" LEADING=\"2\"><P ALIGN=\"CENTER\"><FONT FACE=\"Futura Std Book Fix\" SIZE=\"15\" COLOR=\"#CCCCCC\" KERNING=\"0\">" +
                            content + "</FONT></P></TEXTFORMAT>";
                    }), 100);
                }
                AddCritTooltip(
                    agentInfoSheet, "m_HitBox",
                    agentInfoSheet.m_AgentIcon._x + agentInfoSheet.m_AgentIcon.m_Success._x * agentInfoSheet.m_AgentIcon.m_Success._xscale / 100,
                    agentInfoSheet.m_AgentIcon._y + agentInfoSheet.m_AgentIcon.m_Success._y * agentInfoSheet.m_AgentIcon.m_Success._xscale / 100,
                    agentInfoSheet.m_AgentIcon.m_Success._width,
                    agentInfoSheet.m_AgentIcon.m_Success._height,
                    agentInfoSheet.m_AgentIcon._xscale,
                    crit["str"]
                );
                AddCritTooltip(
                    missionDetail, "m_HitBox",
                    missionDetail.m_Agent._x + missionDetail.m_Agent.m_Success._x * missionDetail.m_Agent.m_Success._xscale / 100,
                    missionDetail.m_Agent._y + missionDetail.m_Agent.m_Success._y * missionDetail.m_Agent.m_Success._xscale / 100 - 25,
                    missionDetail.m_Agent.m_Success._width,
                    missionDetail.m_Agent.m_Success._height,
                    missionDetail.m_Agent._xscale,
                    crit["str"]
                );
            }
        }
        missionDetail.SignalClose.Connect(ClearMatches, this);
        missionDetail.SignalClose.Connect(ScheduleResort, this);
        missionDetail.SignalStartMission.Connect(ClearMatches, this);
        missionDetail.SignalStartMission.Connect(ScheduleResort, this);
        missionDetail.SignalStartMission.Connect(SaveAgent, this);

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

    private function GetDiffuculty(id)
    {
        var AgentMissionDifficulties:Array =
            [
                [], // 0 or 263
                [2801, 274, 2810, 400, 339, 405, 319, 317, 346, 343, 392, 381, 2785, 370, 2803, 453, 2809, 434, 328, 336, 384, 371, 2781, 407, 409, 448, 450, 2813, 318, 334, 406, 2811, 324, 348, 2812, 366, 2802, 312, 2788, 2804, 449, 315, 2787, 402, 320, 345, 373, 313], // 1  or 268
                [395, 291, 295, 349, 298, 408, 435, 433, 286, 399, 362, 350, 2808, 374, 432, 2805, 358, 2784, 316, 443, 444, 369, 437, 387, 570, 321, 326, 329, 365, 569, 386, 417, 418, 415, 445, 452, 361, 342, 390, 429, 440, 388, 331, 2806, 337, 566, 391, 383, 422, 413, 424, 567, 439, 423, 378, 333, 568, 382, 426, 284, 3047, 347, 565, 393, 420, 341, 385, 2807], //2  or 269
                [379, 288, 296, 380, 404, 335, 340, 353, 375, 367, 412, 323, 352, 364, 389, 416, 442, 351, 2790, 411, 441, 454, 289, 292, 325, 368, 363, 421], //3 or 270
                [302, 438, 285, 297, 322, 327, 360, 376, 290, 330, 309]    //4  or 299
            ];
        /*
        var sum = 0;
        for (var i in AgentMissionDifficulties)
        {
            sum += AgentMissionDifficulties[i].length;
        }
        com.GameInterface.UtilsBase.PrintChatText("Supported missions " + sum);
        */
        for (var i in AgentMissionDifficulties)
        {
            for (var y in AgentMissionDifficulties[i])
            {
                if (AgentMissionDifficulties[i][y] == id)
                {
                    return [Number(i)];
                }
            }
        }
        //com.GameInterface.UtilsBase.PrintChatText("missing id " + id);
        return [0, 1, 2, 3, 4] // 263, 268, 269, 270, 299
    }

    private function CalculateCrit(missionData:AgentSystemMission, agent:AgentSystemAgent, totalSuccess:Number)
    {
        var agentStats:Array = AgentSystem.GetAgentOverride(agent.m_AgentId);
        var agentTraits:Array = [agent.m_Trait1, agent.m_Trait2, agentStats[4]];
        var DoubleWeights = [0.7, 0.3];
        var TripleWeights = [0.6, 0.3, 0.1];
        var StarValues:Array = [0, 40, 80, 120, 160, 1];
        var MissionDifficulties:Array = GetDiffuculty(missionData.m_MissionId);

        var MissionDifficultyValues =
            [
                [1, 30, 40, 60, 120], // 1 star mission
                [1, 100, 160, 220, 280], // 2 star mission
                [1, 170, 260, 350, 440], // 3 star mission
                [1, 240, 360, 480, 600], // 4 star mission
                [1, 280, 400, 520, 580], // 5 star mission
                [1, 1, 1, 1, 1, 1] // special mission
            ];

        var maxCritChance = [0, 25, 20, 15, 10];
        var critChanceMultiplier = [0, 0.025, 0.05, 0.02, 0.02];
        var ret:String = "\n";
        var matches = 0;
        var closest;
        for (var i = 0; i < MissionDifficulties.length; i++)
        {
            var missionDifficulty = MissionDifficulties[i];
            var missionDifficultyValue = MissionDifficultyValues[missionData.m_StarRating - 1][missionDifficulty];
            var SuccessStatSum = 0;
            var missionStarValue = StarValues[missionData.m_StarRating - 1];
            if (missionData.m_Stat1Requirement != 0 && missionData.m_Stat2Requirement != 0 && missionData.m_Stat3Requirement != 0)
            {
                if (missionData.m_Stat1Requirement > missionData.m_Stat2Requirement && missionData.m_Stat2Requirement > missionData.m_Stat3Requirement)
                {
                    SuccessStatSum = (agentStats[0] * TripleWeights[0]) + (agentStats[1] * TripleWeights[1]) + (agentStats[2] * TripleWeights[2])
                }
                else if (missionData.m_Stat1Requirement > missionData.m_Stat3Requirement && missionData.m_Stat3Requirement > missionData.m_Stat2Requirement)
                {
                    SuccessStatSum = (agentStats[0] * TripleWeights[0]) + (agentStats[1] * TripleWeights[2]) + (agentStats[2] * TripleWeights[1])
                }
                else if (missionData.m_Stat1Requirement < missionData.m_Stat2Requirement && missionData.m_Stat2Requirement > missionData.m_Stat3Requirement)
                {
                    SuccessStatSum = (agentStats[0] * TripleWeights[1]) + (agentStats[1] * TripleWeights[0]) + (agentStats[2] * TripleWeights[2])
                }
                else if (missionData.m_Stat1Requirement < missionData.m_Stat3Requirement && missionData.m_Stat3Requirement > missionData.m_Stat2Requirement)
                {
                    SuccessStatSum = (agentStats[0] * TripleWeights[1]) + (agentStats[1] * TripleWeights[2]) + (agentStats[2] * TripleWeights[0])
                }
                else if (missionData.m_Stat1Requirement < missionData.m_Stat2Requirement && missionData.m_Stat2Requirement < missionData.m_Stat3Requirement)
                {
                    SuccessStatSum = (agentStats[0] * TripleWeights[2]) + (agentStats[1] * TripleWeights[1]) + (agentStats[2] * TripleWeights[0])
                }
                else if (missionData.m_Stat1Requirement < missionData.m_Stat3Requirement && missionData.m_Stat3Requirement < missionData.m_Stat2Requirement)
                {
                    SuccessStatSum = (agentStats[0] * TripleWeights[2]) + (agentStats[1] * TripleWeights[0]) + (agentStats[2] * TripleWeights[1])
                }
            }
            else if (missionData.m_Stat1Requirement != 0 && missionData.m_Stat2Requirement != 0 && missionData.m_Stat3Requirement == 0)
            {
                if (missionData.m_Stat1Requirement > missionData.m_Stat2Requirement)
                {
                    SuccessStatSum = (agentStats[0] * DoubleWeights[0]) + (agentStats[1] * DoubleWeights[1])
                }
                else if (missionData.m_Stat2Requirement > missionData.m_Stat1Requirement)
                {
                    SuccessStatSum = (agentStats[0] * DoubleWeights[1]) + (agentStats[1] * DoubleWeights[0])
                }
            }
            else if (missionData.m_Stat1Requirement != 0 && missionData.m_Stat2Requirement == 0 && missionData.m_Stat3Requirement != 0)
            {
                if (missionData.m_Stat1Requirement > missionData.m_Stat3Requirement)
                {
                    SuccessStatSum = (agentStats[0] * DoubleWeights[0]) + (agentStats[2] * DoubleWeights[1])
                }
                else if (missionData.m_Stat3Requirement > missionData.m_Stat1Requirement)
                {
                    SuccessStatSum = (agentStats[0] * DoubleWeights[1]) + (agentStats[2] * DoubleWeights[0])
                }
            }
            else if (missionData.m_Stat1Requirement == 0 && missionData.m_Stat2Requirement != 0 && missionData.m_Stat3Requirement != 0)
            {
                if (missionData.m_Stat2Requirement > missionData.m_Stat3Requirement)
                {
                    SuccessStatSum = (agentStats[1] * DoubleWeights[0]) + (agentStats[2] * DoubleWeights[1])
                }
                else if (missionData.m_Stat3Requirement > missionData.m_Stat2Requirement)
                {
                    SuccessStatSum = (agentStats[1] * DoubleWeights[1]) + (agentStats[2] * DoubleWeights[0])
                }
            }
            else if (missionData.m_Stat1Requirement != 0 && missionData.m_Stat2Requirement == 0 && missionData.m_Stat3Requirement == 0)
            {
                SuccessStatSum = agentStats[0]
            }
            else if (missionData.m_Stat1Requirement == 0 && missionData.m_Stat2Requirement != 0 && missionData.m_Stat3Requirement == 0)
            {
                SuccessStatSum = agentStats[1]
            }
            else if (missionData.m_Stat1Requirement == 0 && missionData.m_Stat2Requirement == 0 && missionData.m_Stat3Requirement != 0)
            {
                SuccessStatSum = agentStats[2]
            }

            var SuccessChance:Number = (((SuccessStatSum - missionStarValue) / (missionDifficultyValue-missionStarValue)) * 100);
            var CritChance:Number = SuccessChance * critChanceMultiplier[missionDifficulty];
            if (CritChance > maxCritChance[missionDifficulty])
            {
                CritChance = maxCritChance[missionDifficulty]
            }
            if (SuccessChance >= 100) SuccessChance = 100 - CritChance;
            else SuccessChance -= CritChance;

            if (missionData.m_MissionId == 2801 ||
                    missionData.m_MissionId == 2802 ||
                    missionData.m_MissionId == 2803 ||
                    missionData.m_MissionId == 2804 ||
                    missionData.m_MissionId == 2805 ||
                    missionData.m_MissionId == 2809 ||
                    missionData.m_MissionId == 2813)
            {
                if (agent.m_AgentId != 2791)
                {
                    CritChance = 0;
                    SuccessChance = 0;
                }
            }
            else if (missionData.m_MissionId == 2806 ||
                     missionData.m_MissionId == 2807 ||
                     missionData.m_MissionId == 2808 ||
                     missionData.m_MissionId == 2810 ||
                     missionData.m_MissionId == 2811 ||
                     missionData.m_MissionId == 2812)
            {
                if (agent.m_AgentId == 2791)
                {
                    CritChance = 0;
                    SuccessChance = 0;
                }
            }
            CritChance = Math.floor(CritChance);
            SuccessChance = Math.floor(SuccessChance);

            if ( agent.m_AgentId == 181 ) // amir
            {
                SuccessChance += 8;
            }
            else if ( agent.m_AgentId == 204 ) // petru
            {
                CritChance += 5;
            }

            var item:InventoryItem = AgentSystem.GetItemOnAgent(agent.m_AgentId);
            switch (item.m_ACGItem.m_TemplateID0)
            {
                case 9399682:
                    CritChance += 1;
                    break;
                case 9399684:
                    CritChance += 2;
                    break;
                case 9399683:
                    CritChance += 3;
                    break;
            }

            if ( missionData.m_BonusRewards )
            {
                for (var y in missionData.m_BonusTraitCategories)
                {
                    switch (missionData.m_BonusTraitCategories[y])
                    {
                        case 120:
                            if ( AgentHasTrait(agent, 205) || AgentHasTrait(agent, 536) )
                            {
                                CritChance += 2;
                            }
                            break;
                        case 123:
                            if ( AgentHasTrait(agent, 243))
                            {
                                CritChance += 2;
                            }
                            break;
                        case 119:
                            if ( AgentHasTrait(agent, 176) || AgentHasTrait(agent, 2671) )
                            {
                                CritChance += 2;
                            }
                            break;
                        case 118:
                            if ( AgentHasTrait(agent, 541) || AgentHasTrait(agent, 2678) )
                            {
                                CritChance += 2;
                            }
                            break;
                        case 121:
                            if ( AgentHasTrait(agent, 553))
                            {
                                CritChance += 2;
                            }
                            break;
                        case 122:
                            if ( AgentHasTrait(agent, 531) || AgentHasTrait(agent, 555) )
                            {
                                CritChance += 2;
                            }
                            break;
                    }
                }
            }

            if (missionData.m_Rarity == 170)
            {
                for ( var y in missionData.m_BonusTraitCategories)
                {
                    if ( !AgentHasTrait(agent, missionData.m_BonusTraitCategories[y]))
                    {
                        SuccessChance -= 8;
                    }
                }
            }
            if (Math.floor(SuccessChance) + Math.floor(CritChance) == 99)
            {
                SuccessChance += 1;
            }
            if (Math.floor(SuccessChance) + Math.floor(CritChance) > 100) SuccessChance = 100 - CritChance;
            if ( SuccessChance < 0) SuccessChance = 0;
            if ( CritChance < 0) CritChance = 0;
            if ( MissionDifficulties.length > 1)
            {
                if (Number(i) == 0) ret += "Unknown difficulty, possible options:";
                if ( Math.abs(Math.floor(SuccessChance) + Math.floor(CritChance) - totalSuccess) < 2)
                {
                    matches++;
                    ret += "<font color='#FFFF00'>";
                    closest =
                    {
                        str:
                        "Success: " + Math.floor(SuccessChance) + "%\n" +
                        "Outstanding: " + Math.floor(CritChance) + "%\n" +
                        "Max Outstanding: " + maxCritChance[missionDifficulty] + "%",
                        val : [Math.floor(SuccessChance), Math.floor(CritChance)]
                    }
                }
                ret += "\nDifficulty: " + missionDifficulty +
                       ", Success: " + Math.floor(SuccessChance) + "%" +
                       ", Outstanding: " + Math.floor(CritChance) + "%";
                if ( Math.abs(Math.floor(SuccessChance) + Math.floor(CritChance) - totalSuccess) < 2)
                {
                    ret += "</font>";
                }
            }
            else
            {
                return
                {
                    str :
                    "Success: " + Math.floor(SuccessChance) + "%\n" +
                    "Outstanding: " + Math.floor(CritChance) + "%\n" +
                    "Max Outstanding: " + maxCritChance[missionDifficulty] + "%",
                    val : [Math.floor(SuccessChance), Math.floor(CritChance)]
                };
            }

            //ret += "(Success: " + Math.floor(SuccessChance*10)/10 + " Critical: " + Math.floor(CritChance*10)/10 + ")\n";
        }
        if ( matches == 1 )
        {
            return closest;
        }
        return {str:ret, text:["Unknown(?)"]};
    }

    private function AddCritTooltip(parent:MovieClip, name:String, x:Number, y:Number, width:Number, height:Number, scale:Number, critText:String, roster:MovieClip)
    {
        var m_HitBox:MovieClip = parent.createEmptyMovieClip(name, parent.getNextHighestDepth());
        m_HitBox._xscale = m_HitBox._yscale = scale;
        Draw.DrawRectangle(m_HitBox, x, y, width, height, 0xCB0309, 0);
        m_HitBox.onRollOver = Delegate.create(this, function()
        {
            this.Tooltip.Close();
            var m_TooltipData:TooltipData = new TooltipData();
            m_TooltipData.m_Color = 0xEA4D00;
            m_TooltipData.m_Padding = 2;
            m_TooltipData.m_MaxWidth = 250;
            m_TooltipData.AddDescription("<font size='12'>" + critText + "</font>");
            this.Tooltip = TooltipManager.GetInstance().ShowTooltip(undefined, TooltipInterface.e_OrientationVertical, -1, m_TooltipData);
        });
        m_HitBox.onRollOut = m_HitBox.onReleaseOutside = Delegate.create(this, function()
        {
            this.Tooltip.Close();
        });
        if (parent.HitAreaReleaseHandler) m_HitBox.onRelease = Delegate.create(parent, parent.HitAreaReleaseHandler);
        if (roster)
        {
            m_HitBox.onRelease = Delegate.create(this, function()
            {
                if (AgentSystem.HasAgent(roster.data.m_AgentId))
                {
                    parent.SignalAgentSelected.Emit(roster.data);
                }
            });
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

        ScaleAvailableMissions();
        var agent:AgentSystemAgent = _root.agentsystem.m_Window.m_Content.m_AgentInfoSheet.m_AgentData;

        for (var i:Number = 0; i < 5; i++)
        {
            var slotId:String = "m_Slot_" + i;
            var slot:MovieClip = availableMissionList[slotId];

            var agentIcon = slot.m_AgentIcon;
            var missionData:AgentSystemMission = slot.m_MissionData;
            var bonusView = slot.m_BonusView;

            //Force the teaser reward to be the primary mission reward (this undoes the Funcom change to the base UI)
            missionData.m_TeaserReward = missionData.m_Rewards[0];
            slot.UpdateReward();
            slot.m_HitBox.removeMovieClip();
            if (agent && missionData && missionData.m_MissionId > 0)
            {
                var missionOverride = AgentSystem.GetMissionOverride(missionData.m_MissionId, agent.m_AgentId);
                if ( AgentSystem.HasAgent(agent.m_AgentId))
                {
                    var successChance:Number = AgentSystem.GetSuccessChanceForAgent(agent.m_AgentId, missionData.m_MissionId);
                    agentIcon.m_Success._visible = true;
                    agentIcon.m_Success.m_Text.text = successChance + "%";
                    var crit:Object = CalculateCrit(missionData, agent, successChance);
                    if ( crit["val"] || crit["text"])
                    {
                        agentIcon.m_Success.m_Text.multiline = true;
                        agentIcon.m_Success.m_Text.autoSize = "center";
                        var content = crit["val"] ? crit["val"][0] + " + " + crit["val"][1] : crit["text"];
                        agentIcon.m_Success.m_Text.htmlText = 
                            "<TEXTFORMAT INDENT=\"0\" LEFTMARGIN=\"0\" RIGHTMARGIN=\"0\" LEADING=\"2\"><P ALIGN=\"CENTER\"><FONT FACE=\"Futura Std Book Fix\" SIZE=\"37\" COLOR=\"#CCCCCC\" KERNING=\"0\">" +
                            successChance + "%</FONT></P></TEXTFORMAT>" +
                            "<TEXTFORMAT INDENT=\"0\" LEFTMARGIN=\"0\" RIGHTMARGIN=\"0\" LEADING=\"2\"><P ALIGN=\"CENTER\"><FONT FACE=\"Futura Std Book Fix\" SIZE=\"15\" COLOR=\"#CCCCCC\" KERNING=\"0\">" +
                            content + "</FONT></P></TEXTFORMAT>";
                    }
                    AddCritTooltip(
                        slot, "m_HitBox",
                        slot.m_AgentIcon._x + slot.m_AgentIcon.m_Success._x * slot.m_AgentIcon.m_Success._xscale / 100,
                        slot.m_AgentIcon._y + slot.m_AgentIcon.m_Success._y * slot.m_AgentIcon.m_Success._xscale / 100,
                        slot.m_AgentIcon.m_Success._width,
                        slot.m_AgentIcon.m_Success._height,
                        slot.m_AgentIcon._xscale,
                        crit["str"] || crit["text"]
                    );
                    SetMissionSlotTimer(slot, missionData, missionOverride);
                    UpdateRewards(slot, missionData, missionOverride);
                }
                if (BonusIsMatch(agent, missionData))
                {
                    bonusView.m_Header.textColor = 0x00FF00
                }
                else
                {
                    bonusView.m_Header.textColor = 0xFFFFFF
                }
            }
            else if (missionData && missionData.m_MissionId > 0)
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
                    if (IsImportant(item))
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
                    if (IsImportant(item))
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
    
    private function SaveAgent(missionID:Number, agentID:Number)
    {
        var found:Boolean;
        for (var i in SavedAgents)
        {
            if ( SavedAgents[i][0] == missionID)
            {
                SavedAgents[i][1] = agentID;
                found = true;
                break;
            }
        }
        if (!found) SavedAgents.push([missionID, agentID]);
    }

    private function UpdateAgentDisplay(agent:AgentSystemAgent)
    {
        var agentInfoSheet:MovieClip = _root.agentsystem.m_Window.m_Content.m_AgentInfoSheet;
        if (!agentInfoSheet)
        {
            return;
        }

        if (!agent)
        {
            agent = agentInfoSheet.m_AgentData;
        }

        var missionDetail = _root.agentsystem.m_Window.m_Content.m_MissionDetail;
        if (missionDetail)
        {
            var missionData:AgentSystemMission = missionDetail.m_MissionData;
            var successChance:Number = AgentSystem.GetSuccessChanceForAgent(agent.m_AgentId, missionData.m_MissionId);
            var crit:Object = CalculateCrit(missionData, agent, successChance);
            missionDetail.m_HitBox.removeMovieClip();
            agentInfoSheet.m_HitBox.removeMovieClip();
            if ( AgentSystem.HasAgent(agent.m_AgentId))
            {
                if ( crit["val"] || crit["text"])
                {
                    setTimeout(Delegate.create(this, function()
                    {
                        if (agentInfoSheet && missionDetail)
                        {
                            var content = crit["val"] ? crit["val"][0] + " + " + crit["val"][1] : crit["text"];
                            agentInfoSheet.m_AgentIcon.m_Success.m_Text.multiline = true;
                            agentInfoSheet.m_AgentIcon.m_Success.m_Text.autoSize = "center";
                            agentInfoSheet.m_AgentIcon.m_Success.m_Text.htmlText =
                                "<TEXTFORMAT INDENT=\"0\" LEFTMARGIN=\"0\" RIGHTMARGIN=\"0\" LEADING=\"2\"><P ALIGN=\"CENTER\"><FONT FACE=\"Futura Std Book Fix\" SIZE=\"37\" COLOR=\"#CCCCCC\" KERNING=\"0\">" +
                                successChance + "%</FONT></P></TEXTFORMAT>" +
                                "<TEXTFORMAT INDENT=\"0\" LEFTMARGIN=\"0\" RIGHTMARGIN=\"0\" LEADING=\"2\"><P ALIGN=\"CENTER\"><FONT FACE=\"Futura Std Book Fix\" SIZE=\"15\" COLOR=\"#CCCCCC\" KERNING=\"0\">" +
                                content + "</FONT></P></TEXTFORMAT>";
                            missionDetail.m_Agent.m_Success.m_Text.multiline = true;
                            missionDetail.m_Agent.m_Success.m_Text.autoSize = "center";
                            missionDetail.m_Agent.m_Success.m_Text.htmlText =
                                "<TEXTFORMAT INDENT=\"0\" LEFTMARGIN=\"0\" RIGHTMARGIN=\"0\" LEADING=\"2\"><P ALIGN=\"CENTER\"><FONT FACE=\"Futura Std Book Fix\" SIZE=\"37\" COLOR=\"#CCCCCC\" KERNING=\"0\">" +
                                successChance + "%</FONT></P></TEXTFORMAT>" +
                                "<TEXTFORMAT INDENT=\"0\" LEFTMARGIN=\"0\" RIGHTMARGIN=\"0\" LEADING=\"2\"><P ALIGN=\"CENTER\"><FONT FACE=\"Futura Std Book Fix\" SIZE=\"15\" COLOR=\"#CCCCCC\" KERNING=\"0\">" +
                                content + "</FONT></P></TEXTFORMAT>";
                        }
                    }), 100);
                }
                AddCritTooltip(
                    agentInfoSheet, "m_HitBox",
                    agentInfoSheet.m_AgentIcon._x + agentInfoSheet.m_AgentIcon.m_Success._x * agentInfoSheet.m_AgentIcon.m_Success._xscale / 100,
                    agentInfoSheet.m_AgentIcon._y + agentInfoSheet.m_AgentIcon.m_Success._y * agentInfoSheet.m_AgentIcon.m_Success._xscale / 100,
                    agentInfoSheet.m_AgentIcon.m_Success._width,
                    agentInfoSheet.m_AgentIcon.m_Success._height,
                    agentInfoSheet.m_AgentIcon._xscale,
                    crit["str"]
                );
                AddCritTooltip(
                    missionDetail, "m_HitBox",
                    missionDetail.m_Agent._x + missionDetail.m_Agent.m_Success._x * missionDetail.m_Agent.m_Success._xscale / 100,
                    missionDetail.m_Agent._y + missionDetail.m_Agent.m_Success._y * missionDetail.m_Agent.m_Success._xscale / 100 - 25,
                    missionDetail.m_Agent.m_Success._width,
                    missionDetail.m_Agent.m_Success._height,
                    missionDetail.m_Agent._xscale,
                    crit["str"]
                );
            }
        }

        var healthField:TextField = agentInfoSheet.u_health;
        if (!healthField)
        {
            var m_Timer : TextField = agentInfoSheet.m_Timer;
            healthField = agentInfoSheet.createTextField("u_health", agentInfoSheet.getNextHighestDepth(), m_Timer._x, m_Timer._y, m_Timer._width, m_Timer._height);
            healthField.setNewTextFormat(m_Timer.getTextFormat())
            healthField.embedFonts = true;
        }

        var favoriteField:MovieClip = agentInfoSheet.u_favorite;
        if (!favoriteField)
        {
            var m_Timer : TextField = agentInfoSheet.m_Timer;
            var favoriteText = agentInfoSheet.createTextField("u_favoriteText", agentInfoSheet.getNextHighestDepth(), healthField._x + 80, healthField._y - healthField._height + 3, 50, healthField._height);
            favoriteText.setNewTextFormat(m_Timer.getTextFormat());
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
                if (AgentSystem.GetItemOnAgent(agent.m_AgentId).m_Name)
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
            if (!AgentHasTrait(agent, bonusTrait))
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
            rosterIcon.m_HitBox.removeMovieClip();
            var agent:AgentSystemAgent = rosterIcon.data;
            var traitPanel = rosterIcon.m_TraitCategories;

            for (var t = 0; t < 6; t++)
            {
                traitPanel["u_traitbox" + t].removeMovieClip();
            }
            rosterIcon.m_Frame["u_bonuses"].removeMovieClip();
        }
    }

    private function AddRosterCrit(target:MovieClip, crit:Object, agentId:Number, content:String, successChance)
    {
        if ( target.data.m_AgentId == agentId)
        {
            target.m_Success.m_Text.multiline = true;
            target.m_Success.m_Text.autoSize = "center";
            target.m_Success.m_Text.htmlText = 
                "<TEXTFORMAT INDENT=\"0\" LEFTMARGIN=\"0\" RIGHTMARGIN=\"0\" LEADING=\"2\"><P ALIGN=\"CENTER\"><FONT FACE=\"Futura Std Book Fix\" SIZE=\"37\" COLOR=\"#CCCCCC\" KERNING=\"0\">" +
                successChance + "%</FONT></P></TEXTFORMAT>" +
                "<TEXTFORMAT INDENT=\"0\" LEFTMARGIN=\"0\" RIGHTMARGIN=\"0\" LEADING=\"2\"><P ALIGN=\"CENTER\"><FONT FACE=\"Futura Std Book Fix\" SIZE=\"15\" COLOR=\"#CCCCCC\" KERNING=\"0\">" +
                content + "</FONT></P></TEXTFORMAT>";
        }
    }

    private function HighlightMatchingBonuses()
    {
        var missionDetail = _root.agentsystem.m_Window.m_Content.m_MissionDetail;
        var mission:AgentSystemMission = missionDetail.m_MissionData;

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
            roster["m_HitBox" + i].removeMovieClip();
            if ( rosterIcon.m_Success._visible)
            {
                var successChance:Number = AgentSystem.GetSuccessChanceForAgent(agent.m_AgentId, mission.m_MissionId);
                var crit:Object = CalculateCrit(mission, agent, successChance);
                if ( crit["val"] || crit["text"])
                {
                    var content = crit["val"] ? crit["val"][0] + " + " + crit["val"][1] : crit["text"];
                    setTimeout(Delegate.create(this, AddRosterCrit), 100, rosterIcon, crit, agent.m_AgentId,content, successChance);
                }
                AddCritTooltip(
                    roster, "m_HitBox"+i,
                    rosterIcon._x + rosterIcon.m_Success._x * rosterIcon.m_Success._xscale / 100,
                    rosterIcon._y + rosterIcon.m_Success._y * rosterIcon.m_Success._xscale / 100,
                    rosterIcon.m_Success._width,
                    rosterIcon.m_Success._height,
                    rosterIcon._xscale,
                    crit["str"] || crit["text"],
                    rosterIcon
                );
            }

            //Do it before match checking because some agents have bonuses even without matches.
            DrawAgentBonus(mission, agent, rosterIcon);
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

    private function DrawAgentBonus(mission:AgentSystemMission, agent:AgentSystemAgent, slot:MovieClip)
    {
        var missionOverride:AgentSystemMission = AgentSystem.GetMissionOverride(mission.m_MissionId, agent.m_AgentId);

        //bonus cost calc
        var costIntel:Boolean = missionOverride.m_IntelCost < mission.m_IntelCost;
        var costSupplies:Boolean = missionOverride.m_SuppliesCost < mission.m_SuppliesCost;
        var costAssets:Boolean = missionOverride.m_AssetsCost < mission.m_AssetsCost;

        //bonus rewards calc
        var rewardIntel:Boolean = missionOverride.m_IntelReward > mission.m_IntelReward;
        var rewardSupplies:Boolean = missionOverride.m_SuppliesReward > mission.m_SuppliesReward;
        var rewardAssets:Boolean = missionOverride.m_AssetsReward > mission.m_AssetsReward;

        //bonus crit chance calc
        var outstandingBonus:Boolean = false;
        var matchingAgentTraits:Array = OutstandingData[0];
        for (var i:Number = 0; i < mission.m_BonusTraitCategories.length; i++)
        {
            var cat:Number = mission.m_BonusTraitCategories[i];
            if (OutstandingData[cat] != undefined)
                matchingAgentTraits = matchingAgentTraits.concat(OutstandingData[cat]);
        }
        if (Utils.Contains(matchingAgentTraits, agent.m_Trait1) || Utils.Contains(matchingAgentTraits, agent.m_Trait2))
            outstandingBonus = true;

        var anyBonus:Boolean = costIntel || costSupplies || costAssets || rewardIntel || rewardSupplies || rewardAssets || outstandingBonus;

        if (anyBonus)
            DrawAgentBonusText(costIntel, costSupplies, costAssets, rewardIntel, rewardSupplies, rewardAssets, outstandingBonus, slot);
    }

    private function DrawAgentBonusText(costIntel:Boolean, costSupplies:Boolean, costAssets:Boolean, rewardIntel:Boolean, rewardSupplies:Boolean, rewardAssets:Boolean, outstandingBonus:Boolean, slot:MovieClip)
    {
        var bonusCost:Array = [];
        var bonusRewards:Array = [];

        //cost bonuses
        if (costIntel)
            bonusCost.push("Intel");

        if (costSupplies)
            bonusCost.push("Supplies");

        if (costAssets)
            bonusCost.push("Assets");

        //Rewards bonuses
        if (rewardIntel)
            bonusRewards.push("Intel");

        if (rewardSupplies)
            bonusRewards.push("Supplies");

        if (rewardAssets)
            bonusRewards.push("Assets");

        //default UI setup
        var clip:MovieClip = slot.m_Frame.createEmptyMovieClip("u_bonuses", slot.m_Frame.getNextHighestDepth());

        clip._x = 2;
        clip._y = 146;

        var currentY = 0;
        var maxWidth = 147.6;

        var format:TextFormat = slot.m_Name.getTextFormat();
        format.align = "left";
        format.size = 10;
        format.bold = true;

        //outstanding bonus draw
        if (outstandingBonus)
        {
            clip._y = 132;
            DrawTransparentBackground(22, 0, 103, 12, 0x000000, 50, clip);

            var textfield:TextField = clip.createTextField("m_bonusCrit", clip.getNextHighestDepth(), 22, currentY - 3, 103, 20);
            format.color = Colors.e_ColorCyan;
            textfield.setNewTextFormat(format);
            textfield.embedFonts = true;
            textfield.text = "+ outstanding chance";

            currentY += 12;
        }

        if (bonusCost.length == 0 && bonusRewards.length == 0)
            return;

        var height = 24;
        if (bonusCost.length == 0 || bonusRewards.length == 0)
            height = 12;

        DrawTransparentBackground(0, currentY, maxWidth, height, 0x000000, 50, clip);

        //bonus cost draw
        if (bonusCost.length)
        {
            var text = "- " + bonusCost.join(", ") + " cost";
            var textfield:TextField = clip.createTextField("m_bonusCost", clip.getNextHighestDepth(), 0, currentY - 3, maxWidth, 20);
            format.color = Colors.e_ColorPureRed;
            textfield.setNewTextFormat(format);
            textfield.embedFonts = true;
            textfield.text = text;

            currentY += 12;
        }

        //bonus rewards draw
        if (bonusRewards.length)
        {
            var text = "+ " + bonusRewards.join(", ") + " rewards";
            var textfield:TextField = clip.createTextField("m_bonusRewards", clip.getNextHighestDepth(), 0, currentY - 3, maxWidth, 20);
            format.color = Colors.e_ColorPureGreen;
            textfield.setNewTextFormat(format);
            textfield.embedFonts = true;
            textfield.text = text;
        }
    }

    private function DrawTransparentBackground(x:Number, y:Number, width:Number, height:Number, color:Number, transparency:Number, clip:MovieClip)
    {
        clip.beginFill(color, transparency);
        clip.moveTo(x, y);
        clip.lineTo(x + width, y);
        clip.lineTo(x + width, y + height);
        clip.lineTo(x, y + height);
        clip.lineTo(x, y);
        clip.endFill();
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

    private function AcceptMissionRewards()
    {
        var missions:Array = AgentSystem.GetActiveMissions();
        for (var i in missions)
        {
            if (AgentSystem.IsMissionComplete(missions[i].m_MissionId))
            {
                AgentSystem.AcceptMissionReward(missions[i].m_MissionId);
            }
        }
        UpdateCompleteButton();
    }

    private function UpdateCompleteButton()
    {
        var acceptAllMissionsButton = _root.agentsystem.m_Window.m_Content.m_MissionList.u_acceptAll;
        acceptAllMissionsButton._visible = false;
        var missions:Array = AgentSystem.GetActiveMissions();
        for (var i in missions)
        {
            if (AgentSystem.IsMissionComplete(missions[i].m_MissionId))
            {
                acceptAllMissionsButton._visible = true;
            }
        }
    }
}