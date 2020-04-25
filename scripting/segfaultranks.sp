#pragma semicolon 1 // Force strict semicolon mode.


#define PLUGIN_VERSION "0.9.1"// 1.0.0 release candidate. Needs a few additional things to be ready
#define MESSAGE_PREFIX "[\x05Ranks\x01] "
#define DEBUG_CVAR "sm_segfaultranks_debug"

#define ALIAS_LENGTH 64
#define COMMAND_LENGTH 64

#include <clientprefs>
#include <cstrike>
#include <sdktools>
#include <sourcemod>
#include <sdkhooks>
#include <logdebug>

// for http requests
#include <json>
#include <SteamWorks>

#include "include/segfaultranks.inc"


#define AUTH_METHOD AuthId_Steam2
#define AUTH_METHOD64 AuthId_SteamID64

/** Permissions **/
//StringMap g_PermissionsMap;
ArrayList g_Commands; // just a list of all known pugsetup commands

// Plugin Enabled State
bool pluginEnabled = true; // TODO add a convar to disable this plugin

// Keeps track of if the API has been authorized with yet.
bool apiConnected = true; //TODO SHOULD BE FALSE BY DEFAULT IS TRUE FOR TESTING PURPOSES FOR NOW

// Local cache of state user stats
public UserData userData[MAXPLAYERS + 1];

// leaderboard cache
public LeaderData topTenLeaderboard[10];
public int leaderboardLastLoaded = 0;
public bool leaderboardLoaded = false;
static int cacheTime = 5 * 60; // 5 mins

public void ParseLeaderboardDataIntoCache(char[] jsonBody, LeaderData[] intoCache, int cacheMaxCount)
{
    leaderboardLoaded = false;
    // data should be in an object array format so we get that
    JSON_Array arr = view_as<JSON_Array>(json_decode(jsonBody));
    new i=0;
    while(i < cacheMaxCount) {
        intoCache[i].ClearData();
        if(arr != null) {
            JSON_Object rankObj = arr.GetObject(i);
            if(rankObj != null) {
                intoCache[i].SetFromJson(rankObj);
            }
        }
        i++;
    }

    leaderboardLastLoaded = GetTime();
    leaderboardLoaded = true;
}

// convar local variables
// minimum players required for ranks to calculate
// must be minimum 4 for now (Can't calculate a percent for a team when the percent is always 100 with one person on a team)
// this can be changed if we come up with some new algorithim that still rewards solo players
// one option is having a "minimum required contribution score" to compare against to affect the score
// another option is to use the entire servers players as an average instead of per-team or even use server average for effectiveness value like above
int minimumPlayers = 2;
// minimum rounds played required before user is shown on leaderboard
int minimumRounds = 50;
public char baseApiUrl[64] = "http://localhost:1337/v1";

public bool messageNewRws;


// Forwards
Handle g_hOnHelpCommand = INVALID_HANDLE;

// Convars
ConVar cvarMessagePrefix;
ConVar cvarBaseApiUrl;
ConVar cvarRetakesMode;
// wether or not users can .stats other players
ConVar cvarAllowStatsOtherCommand;
//ConVar cvarMinimumPlayers;
ConVar cvarMinimumRounds;
ConVar cvarMessageNewRws;


#include "segfaultranks/util.sp"
#include "segfaultranks/chat_alias.sp"
#include "segfaultranks/server_functions.sp"
// natives for use by external plugins
#include "segfaultranks/natives.sp"


public Plugin myinfo = {
    name = "CS:GO RWS Ranking System",
    author = "segfault",
    description = "Keeps track of user rankings based on an RWS Elo system",
    version = PLUGIN_VERSION,
    url = "https://segfault.club"
};

public void OnPluginStart() {
    // g_cvarDebugEnabled = CreateConvar(DEBUG_CVAR, "segfaultranks", "is
    // segfaultranks debugging filename?");
    InitDebugLog(DEBUG_CVAR, "segfaultranks");
    LoadTranslations("segfaultranks.phrases");
    LoadTranslations("common.phrases");

    // Initiate the rankings cache Global Adt Array
    // g_steamRankCache = CreateArray(ByteCountToCells(128));

    HookEvents();
    RegisterCommands();
    LoadExtraAliases();
    RegisterConvars();
    RegisterForwards();
    // reloads client hooks for anyone already connected before this finished loading or for when the plugin reloads
    ReloadAllPlayerHooks();
}

void InitializeDatabaseConnection() {

    if (GetFeatureStatus(FeatureType_Native, "SteamWorks_CreateHTTPRequest") != FeatureStatus_Available) {
        LogError("You must have either the SteamWorks extension installed to run segfaultranks");
        SetFailState("Cannot start segfault stats without steamworks extension.");
    }

    // send request to update/init local leaderboard cache
    GetLeaderboardData(minimumRounds);

    //  In here we will verify that the webservice is indeed running, and authorize ourselves with the api

    /*if (GetFeatureStatus(FeatureType_Native, "SteamWorks_CreateHTTPRequest") == FeatureStatus_Available) {
        Handle authRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, url);
        if (authRequest == INVALID_HANDLE) {
            LogError("Failed to create HTTP request using url: %s", url);
            return;
        }

        SteamWorks_SetHTTPCallbacks(authRequest, SteamWorks_OnMapRecieved);
        SteamWorks_SetHTTPRequestContextValue(authRequest, replyToSerial, replySource);
        SteamWorks_SetHTTPRequestGetOrPostParameter(authRequest, "user", username);
        SteamWorks_SetHTTPRequestGetOrPostParameter(authRequest, "password", password);
        SteamWorks_SendHTTPRequest(authRequest);

    } else {
        LogError("You must have either the SteamWorks extension installed to get the current motw");
    }*/
   
}

void HookEvents() {
    HookEvent("bomb_defused", Event_Bomb);
    HookEvent("bomb_planted", Event_Bomb);
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("player_spawned", Event_PlayerSpawned);
    //HookEvent("player_hurt", Event_DamageDealt_Pre, EventHookMode_Pre);
    HookEvent("round_end", Event_RoundEnd);
}

void RegisterCommands() {
    g_Commands = new ArrayList(COMMAND_LENGTH);
    RegAdminCmd("sm_dumprws", Command_DumpRWS, ADMFLAG_KICK,"Dumps all player historical rws and rounds played");
    //RegAdminCmd("sm_testsend", Command_TestSend, ADMFLAG_KICK,"Sends a fake test-round to the database for testing purposes. Will be removed before release.");
    AddUserCommand("rws", Command_RWS, "Show player's historical rws");
    AddUserCommand("rank", Command_Rank, "Show player's ELO Rank");
    AddUserCommand("leaderboard", Command_Leaderboard,"Show player's leaderboard position");
}

static void AddUserCommand(const char[] command, ConCmd callback, const char[] description, 
    /*Permission p = Permission_All,*/ ChatAliasMode mode = ChatAlias_Always) {
    char smCommandBuffer[64];
    Format(smCommandBuffer, sizeof(smCommandBuffer), "sm_%s", command);
    g_Commands.PushString(smCommandBuffer);
    RegConsoleCmd(smCommandBuffer, callback, description);
    //SegfaultRanks_SetPermissions(smCommandBuffer, p);//for now all of the "UserCommands" are unpermissioned and admin commands have no place there
    
    char dotCommandBuffer[64];
    Format(dotCommandBuffer, sizeof(dotCommandBuffer), ".%s", command);
    SegfaultRanks_AddChatAlias(dotCommandBuffer, smCommandBuffer, mode);
}

void RegisterConvars() {

    cvarMessagePrefix = CreateConVar("sm_segfaultranks_message_prefix", "[{PURPLE}Ranks{NORMAL}]","The tag applied before plugin messages. If you want no tag, you can set an empty string here.");

    cvarBaseApiUrl = CreateConVar("segfaultranks_api_url", "http://localhost:1337/v1", "Whether players can use the .rws or !rws command on other players");

    cvarRetakesMode = CreateConVar("segfaultranks_retakesmode_enabled", "0", "determines wether or not bomb planting is rewarded");
    cvarAllowStatsOtherCommand = CreateConVar("sm_segfaultranks_allow_stats_other", "1", "Whether players can use the .rws or !rws command on other players");
    //cvarMinimumPlayers = CreateConVar("sm_segfaultranks_minimumplayers", "2", "Minimum players to start giving points", _, true, 0.0);
    cvarMinimumRounds = CreateConVar("sm_segfaultrank_minimal_rounds", "50","Minimal rounds played for rank to be displayed on leaderboard", _, true, 0.0);

    cvarMessageNewRws = CreateConVar("sm_segfaultrank_newrws_message", "1", "Wether or not new stats for users are sent to chat.");

    AutoExecConfig(true, "segfaultranks", "sourcemod");
}

void GetCvarValues() {
    //minimumPlayers = cvarMinimumPlayers.IntValue;
    minimumRounds = cvarMinimumRounds.IntValue;
    cvarBaseApiUrl.GetString(baseApiUrl, sizeof(baseApiUrl));
    messageNewRws = cvarMessageNewRws.BoolValue;
}

void RegisterForwards() {
    g_hOnHelpCommand = CreateGlobalForward("SegfaultRanks_OnHelpCommand", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_CellByRef);
}

public void OnConfigsExecuted() {
    GetCvarValues();
    InitializeDatabaseConnection();

    // if players have connected before configs load we have to make sure we load them here
    ReloadAllPlayers();
}

public void OnClientPostAdminCheck(int client) {
    LogDebug("OnClientPostAdminCheck: %i", client);
    HookClient(client);
}

HookClient(int client) {
    if (GetFeatureStatus(FeatureType_Capability, "SDKHook_DmgCustomInOTD") == FeatureStatus_Available) {
        if(IsPlayer(client)) {
            SDKHook(client, SDKHook_OnTakeDamageAlive, OnTakeDamageAlive);
            userData[client].did_hook = true;
        }
    } else {
        LogError("Feature SDKHook_DmgCustomInOTD was not availible. Failed to hook player damage event");
    }
}

public void OnClientAuthorized(int client, const char[] auth) {
    LogDebug("OnClientAuthorized: %i auth: %s", client, auth);
    if(client > 0 && client <= MaxClients && !StrEqual("BOT", auth, false) && !StrEqual("GOTV", auth, false)) {
        userData[client].ClearData();
        strcopy(userData[client].steamid2, 64, auth);
        LogDebug("Client %i copied auth: %s", client, userData[client].steamid2);
        ReloadClient(client);
    }
}

ReloadAllPlayerHooks() {
    for (int i = 1; i <= MaxClients; i++) {
        if(IsPlayer(i)) {
            HookClient(i);
        }
    }
}

void ReloadAllPlayers() {
    for (int i = 1; i <= MaxClients; i++) {
        if(IsPlayer(i)) {
            ReloadClient(i);
        }
    }
}

void ReloadClient(int client) {
    if (apiConnected) {
        LogDebug("Started Load operation for client %i.", client);
        LoadPlayer(client);
    } else {
        LogDebug("Could not load client %i, api is not connected!", client);
    }
}

public void LoadPlayer(int client) {
    // Clear any previous users data stored in this cache slot
    //userData[client].ClearData();

    char name[MAX_NAME_LENGTH];
    GetClientName(client, name, sizeof(name));
    ReplaceString(name, sizeof(name), "'", "");
    strcopy(userData[client].display_name, MAX_NAME_LENGTH, name);

    GetClientAuthId(client, AUTH_METHOD, userData[client].steamid2, 64);
    TrimString(userData[client].steamid2);

    LogDebug("Added client %i auth id %s", client, userData[client].steamid2);

    //TODO: CACHE PLAYERS DATABASE INDEX IN A CLIENTPREFS COOKIE SO WE CAN JUST LOAD THEM USING THE INDEX API AND AVOID RUNNING THE STEAMID LOOKUP EVERY TIME

    // Now that we have loaded the clients steam auth and username, it is time to initialize them on the database or load them
    //userData[client].LoadData();
    InitUser(client);
}

public void OnPluginEnd() {
    if (!pluginEnabled) {
        return;
    }
}

// Chat alias listener
public void OnClientSayCommand_Post(int client, const char[] command, const char[] sArgs) {
    if (!IsPlayer(client))
        return;
    
    // splits to find the first word to do a chat alias command check
    char chatCommand[COMMAND_LENGTH];
    char chatArgs[255];
    int index = SplitString(sArgs, " ", chatCommand, sizeof(chatCommand));
    
    if (index == -1) {
        strcopy(chatCommand, sizeof(chatCommand), sArgs);
    } else if (index < strlen(sArgs)) {
        strcopy(chatArgs, sizeof(chatArgs), sArgs[index]);
    }
    
    if (chatCommand[0]) {
        char alias[ALIAS_LENGTH];
        char cmd[COMMAND_LENGTH];
        for (int i = 0; i < GetArraySize(g_ChatAliases); i++) {
            GetArrayString(g_ChatAliases, i, alias, sizeof(alias));
            GetArrayString(g_ChatAliasesCommands, i, cmd, sizeof(cmd));
            if (CheckChatAlias(alias, cmd, chatCommand, chatArgs, client, g_ChatAliasesModes.Get(i))) {
                break;
            }
        }
    }
    
    if (StrEqual(sArgs[0], ".help", false)) {
        const int msgSize = 128;
        ArrayList msgs = new ArrayList(msgSize);
        
        msgs.PushString("{PURPLE}.stats {NORMAL}displays your stats");
        msgs.PushString("{PURPLE}.top {NORMAL}shows the leaderboard");
        msgs.PushString("{PURPLE}.rank {NORMAL}see your current ranking");
        msgs.PushString("{PURPLE}.segfault {NORMAL}cause a segmentation violation");
        
        bool block = false;
        Call_StartForward(g_hOnHelpCommand);
        Call_PushCell(client);
        Call_PushCell(msgs);
        Call_PushCell(msgSize);
        Call_PushCellRef(block);
        Call_Finish();
        
        if (!block) {
            char msg[msgSize];
            for (int i = 0; i < msgs.Length; i++) {
                msgs.GetString(i, msg, sizeof(msg));
                SegfaultRanks_Message(client, msg);
            }
        }
        
        delete msgs;
    }
    
    // Allow using .map as a map-vote revote alias and as a
    // shortcut to the mapchange menu (if avaliable).
    // if (StrEqual(sArgs, ".map") || StrEqual(sArgs, "!revote")) {
    // 	if (IsVoteInProgress() && IsClientInVotePool(client)) {
    // 		RedrawClientVoteMenu(client);
    // 	} else if (g_IRVActive) {
    // 		ResetClientVote(client);
    // 		ShowInstantRunoffMapVote(client, 0);
    // 	} else if (PugSetup_IsPugAdmin(client) && g_DisplayMapChange) {
    // 		PugSetup_GiveMapChangeMenu(client);
    // 	}
    // }
}

static bool CheckChatAlias(const char[] alias, const char[] command, const char[] chatCommand, 
    const char[] chatArgs, int client, ChatAliasMode mode) {
    if (StrEqual(chatCommand, alias, false)) {
        if (mode == ChatAlias_NoWarmup && CheckIfWarmup()) {
            return false;
        }
        
        // Get the original cmd reply source so it can be restored after the fake client command.
        // This means and ReplyToCommand will go into the chat area, rather than console, since
        // *chat* aliases are for *chat* commands.
        ReplySource replySource = GetCmdReplySource();
        SetCmdReplySource(SM_REPLY_TO_CHAT);
        char fakeCommand[256];
        Format(fakeCommand, sizeof(fakeCommand), "%s %s", command, chatArgs);
        FakeClientCommand(client, fakeCommand);
        SetCmdReplySource(replySource);
        return true;
    }
    return false;
}

// Hook when the player spawns so we can update things at the beginning of a new round
public Action Event_PlayerSpawned(Event event, const char[] name, bool dontBroadcast) {
    int client = event.GetInt("userid");
    // only set data if they are a valid player
    if (IsPlayer(client)) {
        // set client did_spawn so we know that they started this round alive (for avoiding ranking mid-round join players a zero score)
        userData[client].did_spawn = true;
    }
}

// Points Events
/**
 * These events update player "rounds points" for computing rws at the end of
 * each round.
 */

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
    if (CheckIfWarmup()) {
        return;
    }

    int victim = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));

    bool validAttacker = IsValidClient(attacker);
    bool validVictim = IsValidClient(victim);

    if (validAttacker && validVictim && HelpfulAttack(attacker, victim)) {
        userData[attacker].round_points += 100;
        // make sure rws stays displayed correctly
        SetClientRwsDisplay(attacker, userData[attacker].rws);
    }
}

public Action Event_Bomb(Event event, const char[] name, bool dontBroadcast) {
    //  don't count warmup rounds towards RWS
    if (CheckIfWarmup() || GetConVarBool(cvarRetakesMode)) {
        return;
    }

    int client = GetClientOfUserId(event.GetInt("userid"));
    userData[client].round_points += 50;
}

// this is how we hook the user damage, but we are gonna use the admincheck event instead
/*public OnClientPutInServer(client)
{
    if (GetFeatureStatus(FeatureType_Capability, "SDKHook_DmgCustomInOTD") !== FeatureStatus_Available) {
        if(IsPlayer(client)) {
            SDKHook(client, SDKHook_OnTakeDamageAlive, OnTakeDamage);
        }
    } else {
        LogError("Feature SDKHook_DmgCustomInOTD was not availible. Failed to hook player damage event");
    }
}*/


// in theory if we pre_hook the event we can fetch the victims health before dmg_health is removed from it
// this does have more chance to fail if the plugin is restarted or if it loads after a player is in
// TODO: DO SOME RESEARCH ON WHEN THE "Automatic Unhook" happens to see if we should hook inside the onPluginLoad players reload without it causing a double hook or something
public Action OnTakeDamageAlive(int victim, int& attacker, int& inflictor, float& damage, int& damagetype, int& weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
    if (CheckIfWarmup()) {
        return Plugin_Continue;
    }

    //int attacker = GetClientOfUserId(event.GetInt("attacker"));
    //int victim = GetClientOfUserId(event.GetInt("userid"));
    bool validAttacker = IsValidClient(attacker);
    bool validVictim = IsValidClient(victim);

    //temporary debug print to verify that this function does in fact do what we think it does
    // if(validVictim) {
    //     PrintToServer("Victim %i had %i health before taking %f damage.", victim, GetClientHealth(victim), damage);
    // }

    if (validAttacker && validVictim && HelpfulAttack(attacker, victim)) {
        // fetch clients health before damage is applied after this hook
        int health = GetClientHealth(victim);
        // fetch the events damage ammount
        //int damage = event.GetInt("dmg_health");

        /* Currently this gives quite boosted stats (maybe)
        // reward more for killing armoured opponents (should reduce how much eco-fragging is rewarded)
        int armor = GetClientArmor(victim);
        // compress damage value into value between 0 and 1
        float damageFactor = 1.0 - (1.0 / (damage + 1.0));
        // set the reward as half of the victims armor times the damage factor
        // (if a user does 100 damage they get half the victims armor as points)
        float armorReward = (float(armor) * 0.5) * damageFactor;
        // add the armor reward to clients points
        userData[attacker].round_points += RoundFloat(armorReward);
        */

        // if health before damage application is less than the total damage ammount
        // then apply the users health ammount instead of the total ammount of damage
        // this should solve awp-headshots over-rewarding as well as allow for proper ADR calculations later
        if(health < damage) {
            userData[attacker].round_points += health;
        } else {
            userData[attacker].round_points += RoundFloat(damage);
        }
    }
    return Plugin_Continue;
}

public bool HelpfulAttack(int attacker, int victim) {
    if (!IsValidClient(attacker) || !IsValidClient(victim)) {
        return false;
    }
    int ateam = GetClientTeam(attacker);
    int vteam = GetClientTeam(victim);
    return ateam != vteam && attacker != victim;
}

void CheckLeaderboardCache() {
    if(GetTime() - leaderboardLastLoaded > cacheTime) {
        GetLeaderboardData(minimumRounds);
    }
}

/**
 * Round end event, updates rws values for everyone.
 */
public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) {

    CheckLeaderboardCache();

    if (ShouldRank()) {
        int winner = event.GetInt("winner");

        int totalPlayers = 0;
        int total_round_points = 0;
        int winnerPlayers = 0;
        int winner_round_points = 0;
        int loserPlayers = 0;
        int loser_round_points = 0;

        for (int i = 1; i <= MaxClients; i++) {
            if (OnActiveTeam(i)) {
                totalPlayers++;
                total_round_points += userData[i].round_points;
                if (GetClientTeam(i) == winner) {
                    winner_round_points += userData[i].round_points;
                    winnerPlayers++;
                } else {
                    loser_round_points += userData[i].round_points;
                    loserPlayers++;
                }
            }
        }

        for (int i = 1; i <= MaxClients; i++) {
            if (IsPlayer(i) && IsOnDb(i)) {
                int team = GetClientTeam(i);
                if (team == CS_TEAM_CT || team == CS_TEAM_T) {
                    bool didWin = team == winner;
                    if(didWin) {
                        RoundUpdate(i, didWin, winnerPlayers, winner_round_points, totalPlayers, total_round_points);
                    } else {
                        RoundUpdate(i, didWin, loserPlayers, loser_round_points, totalPlayers, total_round_points);
                    }
                    // run a check to make sure the user was initiated and hooked
                    CheckUser(i);
                }
            }
        }
    }

    // reset the players in another loop afterwards so that total_points count is not affected
    for (int i = 1; i <= MaxClients; i++) {
        if (IsPlayer(i) && IsOnDb(i)) {
            userData[i].ResetRound();
        }
    }
}

void CheckUser(int client) {
    if(userData[client].did_hook == false ) {
        // this user was never hooked for some reason, so lets hook them
        HookClient(client);
    }

    if(IsOnDb(client) == false) {
        // this user has not yet been initiated on the db for whatever reason, so lets resend that request
        ReloadClient(client);
    }
}

/**
 * Here we apply magic updates to a player's rws based on the previous round.
 */
static void RoundUpdate(int client, bool winner, int teamPlayers, int team_round_points, int totalPlayers, int total_round_points) {
    if(!OnActiveTeam(client)/* || !userData[client].did_spawn*/ ){
        PrintToServer("client %i was not on an active team or did not spawn this round", client);
        return;
    }//avoid submitting rounds for spectators or mid-round joiners
// todo make minimumEnemies a cvar
// todo make minimumTeam
// there needs to be at least two on each team for now until the system is fixed to reward solo players correctly
#define minimumEnemies 1
#define minimumTeam 1

    //temp debug stuff
    //userData[client].round_points = 100;
    //sum = 500;
    //teamPlayers = 1;
    //totalPlayers = 2;
    // REMOVE ME

    if (teamPlayers >= minimumTeam && totalPlayers - teamPlayers >= minimumEnemies) {
        PrintToServer("RoundUpdate: Conditions met to update round.");
        if(SendNewRound(client, winner, userData[client].round_points, team_round_points, teamPlayers, total_round_points, totalPlayers)) {
            LogDebug("SendNewRound was a success for client: %i", client);
        } else {
            LogDebug("Failed to SendNewRound for client: %i", client);
        }
        if(winner) {
            PrintToServer("client %i won the round and would have had it submitted here", client);
        } else {
            PrintToServer("client %i lost the round and would have had it submitted here", client);
        }

    } else {
        PrintToServer("RoundUpdate: Conditions not met for RoundUpdate. TeamP:%i TotalP:%i ", teamPlayers, totalPlayers);
        return;
    }

}

// void SetClientScoreboard(int client, int value) {
//     CS_SetClientContributionScore(client, value);
// }

// Commands


/*public Action Command_TestSend(int client, int args) {
    if (IsPlayer(client) && IsOnDb(client)) {
        if(SendNewRound(client, true, 200, 700, 5, 1200, 10)) {
            ReplyToCommand(client, "sent in a test round for you, currently with RWS=%f, roundsplayed=%d", userData[client].rws, userData[client].rounds_total);
        } else {
            ReplyToCommand(client, "Sending the new round resulted in an error before it sent.");
        }
    }

    return Plugin_Handled;
}*/

public Action Command_DumpRWS(int client, int args) {
    for (int i = 1; i <= MaxClients; i++) {
        if (IsPlayer(i) && IsOnDb(i)) {
            ReplyToCommand(client, "%L has RWS=%f, roundsplayed=%d", i,
                           userData[i].rws, userData[i].rounds_total);
        }
    }

    return Plugin_Handled;
}

public Action Command_RWS(int client, int args) {
    
    char arg1[32];
    int target;
    if (args >= 1 && GetCmdArg(1, arg1, sizeof(arg1))) {
        if (cvarAllowStatsOtherCommand.IntValue == 0) {
            SegfaultRanks_Message(client, "Checking other player's stats is currently not allowed.");
            return Plugin_Handled;
        }
        target = FindTarget(client, arg1, true, false);
    } else {
        target = client;
    }

    if (target != -1) {
        if (IsOnDb(target)) {
            SegfaultRanks_Message(
                client, "%N has a RWS of %.1f with %d rounds played", target,
                userData[target].rws, userData[target].rounds_total);
        } else {
            SegfaultRanks_Message(
                client, "%N does not currently have stats stored", target);
        }
    } else {
        SegfaultRanks_Message(client, "Usage: .stats <optional player>");
    }

    return Plugin_Handled;
}

public Action Command_Rank(int client, int args) { return Plugin_Handled; }

public Action Command_Leaderboard(int client, int args) { 
    if(!pluginEnabled || client == 0 || !IsClientInGame(client)) {
        return Plugin_Handled;
    }
    
    char pageArg[5];
    GetCmdArg(1,pageArg,sizeof(pageArg));
    int pageNum = 0;
    if(!StrEqual(pageArg,"")){
        pageNum = StringToInt(pageArg);
    }
    if (pageNum > 0) {
        ShowLeaderboard(client,pageNum);
    } else {
        ShowLeaderboard(client,0);
    }

    // check if we need to update the cache after showing the current leaderboard (not before cause it may not load right away)
    // for now we will only check on round ends actually but this may be useful later. I'd like to avoid double sending
    //CheckLeaderboardCache();
    return Plugin_Handled;
}

void ShowLeaderboard(int client, int page){
    if(client == 0 || !IsClientInGame(client)) {
        return;
    }

    if(page > 0) {
        LogDebug("leaderboard pages are not yet implemented.");
    }

    Panel panel = new Panel();
    panel.SetTitle("");
 
    char temp[32];
    new i = 0;
    while(i < 10) {
        topTenLeaderboard[i].GetMenuDisplay(temp, sizeof(temp));
        panel.DrawText(temp);
        i++;
    }

    panel.DrawItem("Close");
    panel.Send(client, MenuHandler_Leaderboard, MENU_TIME_FOREVER);
 
    delete panel;
}

public int MenuHandler_Leaderboard(Menu menu, MenuAction action, int param1, int param2)
{
    // do nothing for now
    // if (action == MenuAction_Select)
    // {
    //     PrintToConsole(param1, "You selected item: %d", param2);
    // }
    // else if (action == MenuAction_Cancel)
    // {
    //     PrintToServer("Client %d's menu was cancelled.  Reason: %d", param1, param2);
    // }
}