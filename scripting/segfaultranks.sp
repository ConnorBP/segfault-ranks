#define PLUGIN_VERSION "0.0.1-dev"
#define MESSAGE_PREFIX "[\x05Ranks\x01] "
#define DEBUG_CVAR "sm_segfaultranks_debug"


#include "include/segfaultranks.inc"

#include <clientprefs>
#include <cstrike>
#include <sdktools>
#include <sourcemod>

#include <logdebug>

// for http requests
#include <json>
#include <SteamWorks>


//#define AUTH_METHOD AuthId_Steam2

// Plugin Enabled State
bool pluginEnabled = true; // TODO add a convar to disable this plugin

// Keeps track of if the API has been authorized with yet.
bool apiConnected = true; //TODO SHOULD BE FALSE BY DEFAULT IS TRUE FOR TESTING PURPOSES FOR NOW

// Local cache of state user stats
public UserData userData[MAXPLAYERS + 1];

// convar local variables
// minimum players required for ranks to calculate
int minimumPlayers = 2;
// minimum rounds played required before user is shown on leaderboard
//int minimumRounds = 0;

// Convars
ConVar cvarMessagePrefix;
// wether or not users can .stats other players
//ConVar cvarAllowStatsOtherCommand;
//ConVar cvarMinimumPlayers;
//ConVar cvarMinimumRounds;


#include "segfaultranks/util.sp"
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
    RegisterConvars();
    RegisterForwards();
}

void InitializeDatabaseConnection() {

    if (GetFeatureStatus(FeatureType_Native, "SteamWorks_CreateHTTPRequest") != FeatureStatus_Available) {
        LogError("You must have either the SteamWorks extension installed to run segfaultranks");
        SetFailState("Cannot start segfault stats without steamworks extension.");
    }
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
    HookEvent("player_hurt", Event_DamageDealt);
    HookEvent("round_end", Event_RoundEnd);
}

void RegisterCommands() {
    RegAdminCmd("sm_dumprws", Command_DumpRWS, ADMFLAG_KICK,"Dumps all player historical rws and rounds played");
    RegAdminCmd("sm_testsend", Command_TestSend, ADMFLAG_KICK,"Sends a fake test-round to the database for testing purposes. Will be removed before release.");
    RegConsoleCmd("sm_rws", Command_RWS, "Show player's historical rws");
    RegConsoleCmd("sm_rank", Command_Rank, "Show player's ELO Rank");
    RegConsoleCmd("sm_top", Command_Leaderboard,"Show player's leaderboard position");

    // SegfaultRanks_AddChatAlias(".rws", "sm_rws");
    // SegfaultRanks_AddChatAlias(".stats", "sm_rws");
    // SegfaultRanks_AddChatAlias(".rank", "sm_rank");
    // SegfaultRanks_AddChatAlias(".top", "sm_top");
}

void RegisterConvars() {

    cvarMessagePrefix = CreateConVar("sm_segfaultranks_message_prefix", "[{PURPLE}Ranks{NORMAL}]","The tag applied before plugin messages. If you want no tag, you can set an empty string here.");

    //cvarAllowStatsOtherCommand = CreateConVar("sm_segfaultranks_allow_stats_other", "1", "Whether players can use the .rws or !rws command on other players");

    //cvarMinimumPlayers = CreateConVar("sm_segfaultranks_minimumplayers", "2", "Minimum players to start giving points", _, true, 0.0);

    //cvarMinimumRounds = CreateConVar("sm_segfaultrank_minimal_rounds", "0","Minimal rounds played for rank to be displayed", _, true, 0.0);

    AutoExecConfig(true, "segfaultranks", "sourcemod");
}

void GetCvarValues() {
    //minimumPlayers = cvarMinimumPlayers.IntValue;
    //minimumRounds = cvarMinimumRounds.IntValue;
}

void RegisterForwards() {
  // None
}

public void OnConfigsExecuted() {
    GetCvarValues();
    InitializeDatabaseConnection();
}

public void OnClientPostAdminCheck(int client) {
    LogDebug("OnClientPostAdminCheck: %i", client);
    ReloadClient(client);
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
    userData[client].ClearData();

    char name[MAX_NAME_LENGTH];
    GetClientName(client, name, sizeof(name));
    ReplaceString(name, sizeof(name), "'", "");
    strcopy(userData[client].display_name, MAX_NAME_LENGTH, name);

    //char auth[32];
    GetClientAuthId(client, AuthId_Steam2, userData[client].steamid2, 64);
    //strcopy(userData[client].steamid2, sizeof(userData[client].steamid2), auth);

    LogDebug("Added client %i auth id %s", client, userData[client].steamid2);

    //TODO: CACHE PLAYERS DATABASE INDEX IN A CLIENTPREFS COOKIE SO WE CAN JUST LOAD THEM USING THE INDEX API AND AVOID RUNNING THE STEAMID LOOKUP EVERY TIME

    // Now that we have loaded the clients steam auth and username, it is time to initialize them on the database or load them
    userData[client].LoadData();
}

public void OnPluginEnd() {
    if (!pluginEnabled) {
        return;
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
    }
}

public Action Event_Bomb(Event event, const char[] name, bool dontBroadcast) {
    //  don't count warmup rounds towards RWS
    if (CheckIfWarmup()) {
        return;
    }

    int client = GetClientOfUserId(event.GetInt("userid"));
    userData[client].round_points += 50;
}

public Action Event_DamageDealt(Event event, const char[] name, bool dontBroadcast) {
    if (CheckIfWarmup()) {
        return;
    }

    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    int victim = GetClientOfUserId(event.GetInt("userid"));
    bool validAttacker = IsValidClient(attacker);
    bool validVictim = IsValidClient(victim);

    if (validAttacker && validVictim && HelpfulAttack(attacker, victim)) {
        int damage = event.GetInt("dmg_health");
        userData[attacker].round_points += damage;
    }
}

public bool HelpfulAttack(int attacker, int victim) {
    if (!IsValidClient(attacker) || !IsValidClient(victim)) {
        return false;
    }
    int ateam = GetClientTeam(attacker);
    int vteam = GetClientTeam(victim);
    return ateam != vteam && attacker != victim;
}

/**
 * Round end event, updates rws values for everyone.
 */
public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) {
    if (!ShouldRank()) {
        // reset round points here anyways so that they don't accidentaly affect
        // the first real round
        // TODO
        for (int i = 1; i <= MaxClients; i++) {
            if (IsPlayer(i) && IsOnDb(i)) {
                userData[i].ResetRound();
            }
        }
        return;
    }

    int winner = event.GetInt("winner");
    for (int i = 1; i <= MaxClients; i++) {
        if (IsPlayer(i) && IsOnDb(i)) {
            int team = GetClientTeam(i);
            if (team == CS_TEAM_CT || team == CS_TEAM_T) {
                RoundUpdate(i, team == winner);
                userData[i].ResetRound();
            }
        }
    }
}

/**
 * Here we apply magic updates to a player's rws based on the previous round.
 */
static void RoundUpdate(int client, bool winner) {
// todo make minimumEnemies a cvar
#define minimumEnemies 1
    int totalPlayers = 0;
    int teamPlayers = 0;
    int sum = 0;
    for (int i = 1; i <= MaxClients; i++) {
        if (IsPlayer(i)) {
            totalPlayers++;
            if (GetClientTeam(i) == GetClientTeam(client)) {
                sum += userData[i].round_points;
                teamPlayers++;
            }
        }
    }

    if (teamPlayers > 0 && totalPlayers - teamPlayers >= minimumEnemies) {
        //int rws = update_on_server();
        if(winner) {
            PrintToServer("client %i won the round and would have had it submitted here", client);
        } else {
            PrintToServer("client %i lost the round and would have had it submitted here", client);
        }

    } else {
        return;
    }

}

// void SetClientScoreboard(int client, int value) {
//     CS_SetClientContributionScore(client, value);
// }

// Commands


public Action Command_TestSend(int client, int args) {
    if (IsPlayer(client)/* && IsOnDb(client)*/) {
        if(SendNewRound(client, true, 300, 600, 5)) {
            ReplyToCommand(client, "sent in a test round for you, currently with RWS=%f, roundsplayed=%d", userData[client].rws, userData[client].rounds_total);
        } else {
            ReplyToCommand(client, "Sending the new round resulted in an error before it sent.");
        }
    }

    return Plugin_Handled;
}

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
    /*if (g_AllowStatsOtherCommandCvar.IntValue == 0) {
        return Plugin_Handled;
    }*/

    char arg1[32];
    int target;
    if (args >= 1 && GetCmdArg(1, arg1, sizeof(arg1))) {
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
        SegfaultRanks_Message(client, "Usage: .stats [player]");
    }

    return Plugin_Handled;
}

public
Action Command_Rank(int client, int args) { return Plugin_Handled; }

public
Action Command_Leaderboard(int client, int args) { return Plugin_Handled; }
