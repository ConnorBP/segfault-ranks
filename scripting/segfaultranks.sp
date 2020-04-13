#define PLUGIN_VERSION "0.0.1-dev"
#define MESSAGE_PREFIX "[\x05Ranks\x01] "
#define DEBUG_CVAR "sm_segfaultranks_debug"

#include <clientprefs>
#include <cstrike>
#include <sdktools>
#include <sourcemod>

#include "include/segfaultranks.inc"
#include "segfaultranks/util.sp"
#include <logdebug>

//#define AUTH_METHOD AuthId_Steam2


bool g_bEnabled = true; // TODO add a convar to disable this plugin

// User Data Cache

// Local cache of state user stats
UserData userData[MAXPLAYERS + 1];

// convar local variables

// minimum players required for ranks to calculate
int g_MinimumPlayers = 2;
int g_RankMode = 1;
// int g_DaysToNotShowOnRank;
int g_MinimalRounds = 0;
bool g_bRankCache = false;

// Convars

ConVar g_MessagePrefixCvar;

ConVar g_AllowStatsOtherCommandCvar;
// ConVar g_RecordStatsCvar;
// ConVar g_cvarAutopurge;
ConVar g_cvarMinimumPlayers;
ConVar g_cvarRankMode;
// ConVar g_cvarDaysToNotShowOnRank;
ConVar g_cvarMinimalRounds;
ConVar g_cvarRankCache;
// ConVar g_RankEachRoundCvar;
// ConVar g_SetEloRanksCvar;
// ConVar g_ShowRWSOnScoreboardCvar
// ConVar g_ShowRankOnScoreboardCvar;

#include "segfaultranks/natives.sp"

public
Plugin myinfo = {name = "CS:GO RWS Ranking System", author = "segfault",
                 description =
                     "Keeps track of user rankings based on an RWS Elo system",
                 version = PLUGIN_VERSION, url = "https://segfault.club"};

public
void OnPluginStart() {
    // g_cvarDebugEnabled = CreateConvar(DEBUG_CVAR, "segfaultranks", "is
    // segfaultranks debugging filename?");
    InitDebugLog(DEBUG_CVAR, "segfaultranks");
    LoadTranslations("segfaultranks.phrases");
    LoadTranslations("common.phrases");

    // Initiate the rankings cache Global Adt Array
    // g_steamRankCache = CreateArray(ByteCountToCells(128));

    InitializeDatabaseConnection();

    HookEvents();
    RegisterCommands();
    RegisterConvars();
    RegisterForwards();
}

void GetCvarValues() {
    g_MinimumPlayers = g_cvarMinimumPlayers.IntValue;
    g_RankMode = g_cvarRankMode.IntValue;
    // g_DaysToNotShowOnRank = g_cvarDaysToNotShowOnRank.IntValue;
    g_MinimalRounds = g_cvarMinimalRounds.IntValue;
    g_bRankCache = g_cvarRankCache.BoolValue;
}

void InitializeDatabaseConnection() {
    //  In here we will initialize a connection to our web service
}

void HookEvents() {
    HookEvent("bomb_defused", Event_Bomb);
    HookEvent("bomb_planted", Event_Bomb);
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("player_hurt", Event_DamageDealt);
    HookEvent("round_end", Event_RoundEnd);
}

void RegisterCommands() {
    RegAdminCmd("sm_dumprws", Command_DumpRWS, ADMFLAG_KICK,
                "Dumps all player historical rws and rounds played");
    RegConsoleCmd("sm_rws", Command_RWS, "Show player's historical rws");
    RegConsoleCmd("sm_rank", Command_Rank, "Show player's ELO Rank");
    RegConsoleCmd("sm_top", Command_Leaderboard,
                  "Show player's leaderboard position");
    // SegfaultRanks_AddChatAlias(".rws", "sm_rws");
    // SegfaultRanks_AddChatAlias(".stats", "sm_rws");
    // SegfaultRanks_AddChatAlias(".rank", "sm_rank");
    // SegfaultRanks_AddChatAlias(".top", "sm_top");
}

void RegisterConvars() {
    g_MessagePrefixCvar = CreateConVar(
        "sm_segfaultranks_message_prefix", "[{PURPLE}Ranks{NORMAL}]",
        "The tag applied before plugin messages. If you want no "
        "tag, you can set an empty string here.");
    g_AllowStatsOtherCommandCvar = CreateConVar(
        "sm_segfaultranks_allow_stats_other", "1",
        "Whether players can use the .rws or !rws command on other players");
    // g_RecordStatsCvar = CreateConVar("sm_segfaultranks_record_stats", "1",
    // "Whether rws should be recorded while not in warmup (set to 0 to disable
    // changing players rws stats)"); g_cvarAutopurge =
    // CreateConVar("sm_segfaultranks_autopurge", "0", "Auto-Purge inactive
    // players? X = Days  0 = Off", _, true, 0.0);
    g_cvarMinimumPlayers =
        CreateConVar("sm_segfaultranks_minimumplayers", "2",
                     "Minimum players to start giving points", _, true, 0.0);
    g_cvarRankMode =
        CreateConVar("sm_segfaultrank_rank_mode", "1",
                     "Rank by what? 1 = by rws 2 = by kdr 3 = by elo", _, true,
                     1.0, true, 3.0);
    // g_cvarDaysToNotShowOnRank = CreateConVar("sm_segfaultrank_timeout_days",
    // "0", "Days inactive to not be shown on rank? X = days 0 = off", _, true,
    // 0.0);
    g_cvarMinimalRounds = CreateConVar(
        "sm_segfaultrank_minimal_rounds", "0",
        "Minimal rounds played for rank to be displayed", _, true, 0.0);
    // g_RankEachRoundCvar = CreateConVar("sm_segfaultranks_rank_rounds", "1",
    // "Sets if Elo ranks should be updated every round instead of at match end.
    // (Useful for retake ranking)"); g_SetEloRanksCvar =
    // CreateConVar("sm_segfaultranks_display_elo_ranks", "2", "Wether or not to
    // display user ranks based on calculated total ELO. (S,G,A,B,etc) 0=Don't
    // Display 1=Calculate elo ranks 2=Use top RWS", _, true, 0.0, true, 2.0);
    // g_ShowRWSOnScoreboardCvar = CreateConVar("sm_segfaultranks_display_rws",
    // "1", "Whether rws stats for current map are to be displayed on the ingame
    // scoreboard in place of points."); g_ShowRankOnScoreboardCvar =
    // CreateConVar("sm_segfaultranks_display_rank", "1", "Whether rws stats for
    // current map are to be displayed on the ingame scoreboard in place of
    // points.");
    g_cvarRankCache = CreateConVar(
        "sm_segfaultranks_rank_cache", "0",
        "Get player rank via cache, auto build cache on every OnMapStart.", _,
        true, 0.0, true, 1.0);

    AutoExecConfig(true, "segfaultranks", "sourcemod");
}

void RegisterForwards() {

}

public
void OnConfigsExecuted() {
    GetCvarValues();
    DB_Init_Stuff();
}

void BuildRankCache() {}

public
void DB_Connect() {}

public
void OnClientPostAdminCheck(int client) {
    LogDebug("OnClientPostAdminCheck: %i", client);
    ReloadClient(client);
}

void ReloadClient(int client) {
    if (g_hStatsDb != INVALID_HANDLE) {
        LogDebug("Client %i in reloadclient db handle is valid!", client);
        LoadPlayer(client);
    } else {
        LogDebug("Client %i in reloadclient db handle is invalid!", client);
    }
}

public
void LoadPlayer(int client) {
    userData[client].on_db = false;
    // stats
    userData[client].Reset();

    LogDebug("Client %i connect time: %i", client,
             g_aSessionConnectedTime[client]);

    char name[MAX_NAME_LENGTH];
    GetClientName(client, name, sizeof(name));
    ReplaceString(name, sizeof(name), "'", "");

    strcopy(g_aClientName[client], MAX_NAME_LENGTH, name);

    char auth[32];
    GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
    strcopy(g_aClientSteam[client], sizeof(g_aClientSteam[]), auth);

    LogDebug("Added client %i auth id %s from received %s", client,
             g_aClientSteam[client], auth);
}

public
void OnPluginEnd() {
    if (!g_bEnabled) {
        return;
    }
}

// Points Events
/**
 * These events update player "rounds points" for computing rws at the end of
 * each round.
 */

public
Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
    if (CheckIfWarmup()) {
        return;
    }

    int victim = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));

    bool validAttacker = IsValidClient(attacker);
    bool validVictim = IsValidClient(victim);

    if (validAttacker && validVictim && HelpfulAttack(attacker, victim)) {
        userData[attacker].ROUND_POINTS += 100;
    }
}

public
Action Event_Bomb(Event event, const char[] name, bool dontBroadcast) {
    //  don't count warmup rounds towards RWS
    if (CheckIfWarmup()) {
        return;
    }

    int client = GetClientOfUserId(event.GetInt("userid"));
    userData[client].ROUND_POINTS += 50;
}

public
Action Event_DamageDealt(Event event, const char[] name, bool dontBroadcast) {
    if (CheckIfWarmup()) {
        return;
    }

    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    int victim = GetClientOfUserId(event.GetInt("userid"));
    bool validAttacker = IsValidClient(attacker);
    bool validVictim = IsValidClient(victim);

    if (validAttacker && validVictim && HelpfulAttack(attacker, victim)) {
        int damage = event.GetInt("dmg_health");
        userData[attacker].ROUND_POINTS += damage;
    }
}

public
bool HelpfulAttack(int attacker, int victim) {
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
public
Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) {
    if (!ShouldRank()) {
        // reset round points here anyways so that they don't accidentaly affect
        // the first real round
        // TODO
        for (int i = 1; i <= MaxClients; i++) {
            if (IsPlayer(i) && IsOnDb(i)) {
                userData[i].ROUND_POINTS = 0;
            }
        }
        return;
    }

    int winner = event.GetInt("winner");
    for (int i = 1; i <= MaxClients; i++) {
        if (IsPlayer(i) && IsOnDb(i)) {
            int team = GetClientTeam(i);
            if (team == CS_TEAM_CT || team == CS_TEAM_T) {
                RWSUpdate(i, team == winner);
            }
        }
    }
    for (int i = 1; i <= MaxClients; i++) {
        if (IsPlayer(i) && IsOnDb(i)) {
            userData[i].ROUND_POINTS = 0;
            SavePlayerData(i);
        }
    }
}

/**
 * Here we apply magic updates to a player's rws based on the previous round.
 */
static void RWSUpdate(int client, bool winner) {
// todo make minimumEnemies a cvar
#define minimumEnemies 1
    int totalPlayers = 0;
    int teamPlayers = 0;
    int sum = 0;
    for (int i = 1; i <= MaxClients; i++) {
        if (IsPlayer(i)) {
            totalPlayers++;
            if (GetClientTeam(i) == GetClientTeam(client)) {
                sum += userData[i].ROUND_POINTS;
                teamCount++;
            }
        }
    }

    if (teamCount > 0 && totalPlayers - teamCount >= minimumEnemies) {
        rws = update_on_server();
        localRws cache = serverRws localRoundsPlayed = serverROunds

    } else {
        return;
    }

    float alpha = GetAlphaFactor(client);
    userData[client].RWS = (1.0 - alpha) * userData[client].RWS + alpha * rws;
    userData[client].ROUNDS_TOTAL++;
    LogDebug("RoundUpdate(%L), alpha=%f, round_rws=%f, new_rws=%f", client,
             alpha, rws, userData[client].RWS);
}

void SetClientScoreboard(int client, int value) {
    CS_SetClientContributionScore(client, value);
}

// some utils (TODO MOVE THIS TO UTIL FILE)

public
bool IsOnDb(int client) { return userData[client].on_db; }

// Re-Usable checks for wether or not we should rank players right now
bool ShouldRank() {
    // ranks should be calculated if it is not warmup, and there are at least
    // the min player count (2 by default)
    // TODO: add check for if ranking is by round or by match either here or
    // somewhere else
    return !CheckIfWarmup() && g_MinimumPlayers > GetCurrentPlayers();
}

// returns true if it is currently the warmup period
bool CheckIfWarmup() { return GameRules_GetProp("m_bWarmupPeriod") == 1; }

// Commands

public
Action Command_DumpRWS(int client, int args) {
    for (int i = 1; i <= MaxClients; i++) {
        if (IsPlayer(i) && IsOnDb(i)) {
            ReplyToCommand(client, "%L has RWS=%f, roundsplayed=%d", i,
                           userData[i].RWS, userData[i].ROUNDS_TOTAL);
        }
    }

    return Plugin_Handled;
}

public
Action Command_RWS(int client, int args) {
    if (g_AllowStatsOtherCommandCvar.IntValue == 0) {
        return Plugin_Handled;
    }

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
                userData[target].RWS, userData[target].ROUNDS_TOTAL);
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
