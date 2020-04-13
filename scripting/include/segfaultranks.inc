#if defined _segfaultranks_included
#endinput
#endif
#define _segfaultranks_included

// id, steam, name, lastip, connected, lastconnected, elo, rws, rounds_total, rounds_won, kills, deaths, assists, suicides, teamkills, headshots, total_damage, mvp, matches_won, matches_lost, matches_tied
//"UPDATE `%s` SET elo = '%i', kills = '%i', deaths='%i', assists='%i',suicides='%i',tk='%i',shots='%i',hits='%i',headshots='%i', rounds_tr = '%i', rounds_ct = '%i',lastip='%s',name='%s'%s,head='%i',chest='%i', stomach='%i',left_arm='%i',right_arm='%i',left_leg='%i',right_leg='%i' WHERE steam = '%s';";

// When float values are stored in the db they are stored as int * 1000 000 (with 6 decimal places basically) and then divided again on return (max float value is aprox 2.4billion so this is fine)
//#define DATABASE_FLOAT_DECIMALS 1000000.0
// this to avoid dividing by zero if the db value is 0
//#define DATABASE_BACK_TO_FLOAT 0.000001

enum struct STATS_NAMES {
    int CONNECTED;//time that the user connected at

    float ELO;//NOT USED CURRENTLY, will be a calculated ELO value

    int ROUND_POINTS; //per-round points used to calculate RWS at the end of round
    float RWS;//player overall RWS value
    int ROUNDS_TOTAL;//total number of rounds the player has played out
    //int ROUNDS_WON;
    //int KILLS;
    //int DEATHS;
    //int ASSISTS;
    //int SUICIDES;
    //int TEAMKILLS;
    //int HEADSHOTS;
    //int TOTAL_DAMAGE
    //int MVP;
    //int MATCHES_WON;
    //int MATCHES_LOST;
    //int MATCHES_TIED;

    void Reset() {
        this.CONNECTED = 0;
        this.ELO = 0.0;
        this.ROUND_POINTS = 0;
        this.RWS = 0.0;
        this.ROUNDS_TOTAL = 0;
        //this.ROUNDS_WON = 0;
        //this.ASSISTS = 0;
        //this.SUICIDES = 0;
        //this.TEAMKILLS = 0;
        //this.HEADSHOTS = 0;
        //this.TOTAL_DAMAGE = 0;
        //this.MVP = 0;
        //this.MATCHES_WON = 0;
        //this.MATCHES_TIED = 0;
    }
    /*int GetDbRWS() {
      return FloatToDb(this.RWS);
    }*/
    /*void GetData(int[] data) {
        data[0] = this.CONNECTED;
        data[2] = this.ELO;
        data[3] = this.RWS;
        data[4] = this.ROUNDS_TOTAL;
        data[5] = this.ROUNDS_WON;
        data[6] = this.ASSISTS;
        data[7] = this.SUICIDES;
        data[8] = this.TEAMKILLS;
        data[9] = this.HEADSHOTS;
        data[10] = this.TOTAL_DAMAGE;
        data[11] = this.MVP;
        data[12] = this.MATCHES_WON;
        data[13] = this.MATCHES_TIED;
    }*/
}

// DB to and From float conversion helpers

// On second thought just storing as float is better
/*int FloatToDb(float inValue) {
  //converts to int (causing rounding off of decimal points) after moving the decimal place 6 places
  return int(inValue * DATABASE_FLOAT_DECIMALS);
}

float FloatFromDb(int dbOutValue) {
  //return our float value after it is in the database
  return float(dbOutValue) * DATABASE_BACK_TO_FLOAT;
}*/

enum ChatAliasMode {
    ChatAlias_Always,     // Alias is always enabled
    ChatAlias_NoWarmup,  // Alias is only available when game is not in warmup
};

// Native Functions

// Adds a chat alias for a command. For example: .setup as a chat trigger for sm_setup
native void SegfaultRanks_AddChatAlias(const char[] alias, const char[] command, ChatAliasMode mode = ChatAlias_Always);

// Prints a plugin-formatted message to a client.
native void SegfaultRanks_Message(int client, const char[] format, any:...);

// Prints a plugin-formatted message to all clients.
native void SegfaultRanks_MessageToAll(const char[] format, any:...);

/*********************************************************
 * Get rank of a player on the server
 *
 * @param client	The client index of the player to get the rank
 * @param callback	The return Callback
 * @param data	Any data you would like that return on the callback
 * @noreturn		
 *********************************************************/
native void SegfaultRanks_GetRank(int client, RankCallback callback, any data = 0);

// Global Forwards

/**********************************************************************
 * When a player has been loaded
 * *
 * @param         client        The client index of the player that has been loaded
 * @noreturn
 **********************************************************************/
forward Action SegfaultRanks_OnPlayerLoaded(int client);

/**********************************************************************
 * When a player has been saved
 * *
 * @param         client        The client index of the player that has been saved
 * @noreturn
 **********************************************************************/
forward Action SegfaultRanks_OnPlayerSaved(int client);

/**
 * Called when a client issues a .help command in chat.
 *
 * @param client The client issuing the command
 * @param replyMessages An ArrayList of Strings to reply with (in chat)
 * @param maxMessageSize The max length of a string in the replyMessages list
 * @param block Whether to block the reply message (set to true to have no reply)
 */
forward void PugSetup_OnHelpCommand(int client, ArrayList replyMessages, int maxMessageSize,bool& block);

public SharedPlugin __pl_segfaultranks = {
    name = "segfaultranks", file = "segfaultranks.smx",
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
};

typedef RankCallback = function Action(int client, int rank, any data);

#if !defined REQUIRE_PLUGIN
public __pl_segfaultranks_SetNTVOptional() {
  MarkNativeAsOptional("SegfaultRanks_Message");
  MarkNativeAsOptional("SegfaultRanks_MessageToAll");
  MarkNativeAsOptional("SegfaultRanks_AddChatAlias");
  MarkNativeAsOptional("SegfaultRanks_GetRank");
}
#endif
