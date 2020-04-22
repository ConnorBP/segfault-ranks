#if defined _segfaultranks_included
#endinput
#endif
#define _segfaultranks_included

/*
db struct:
    pub id: i32,
    pub display_name: String,
    pub steamid2: String,
    pub discord: Option<String>,
    pub elo: f32,
    pub rws: f32,
    pub rounds_total: i32,
*/
enum struct UserData {

  bool on_db;//have they been initialized/retreived from db yet?
  int id;//database id index

  char display_name[MAX_NAME_LENGTH];
  char steamid2[64];
  char discord[18];
  float elo;
  float rws;
  int rounds_total;
  int round_points;

  // for checking if someone started the round alive or not
  bool did_spawn;

  void ClearData() {
    this.on_db = false;

    this.id = 0;
    this.display_name = "";
    this.steamid2 = "";
    this.discord = "";
    this.elo = 0.0;
    this.rws = 0.0;

    this.rounds_total = 0;
    this.round_points = 0;
    this.did_spawn = false;
  }

  void ResetStats() {
    this.elo = 0.0;
    this.rws = 0.0;

    this.rounds_total = 0;
    this.round_points = 0;
  }

  void ResetRound() {
    this.round_points = 0;
    this.did_spawn = false;
  }

  // compares stored steam to double check that the current client id matches the steam of said client id
  // if a user disconnects before a web callback is received we don't want the callback to accidentaly overwrite another user
  bool CheckSteamId(char[] steamId) {
    return StrEqual(steamId, this.steamid2);
  }

  bool ParseFromJson(char[] jsonBody, bool initClient = false) {
    JSON_Object obj = json_decode(jsonBody);
    char jsonSteam[64];
    obj.GetString("steamid2", jsonSteam, sizeof(jsonSteam));
    //if we are not initializing the client we need to double check
    // that the existing steamid is the same as the one this response is for
    if(!initClient && !this.CheckSteamId(jsonSteam)) {//we could probably compare databaseId instead of steam since it is easier to not mess up comparing integers
      // it is not the first-time initialization of the client
      // and the steamid check returned as not a match
      LogError("Warning! There was an attempt to overwrite a user %s with a non matching user %s", this.steamid2, jsonSteam);
      return false;
    }
    // now we know we are safe and it is the same user
    // start updating the local variables from the returned json

    //first decode them

    if(initClient) {
      // only apply dbid on the initialize
      int _id = obj.GetInt("id");
      this.id = _id;
    }

    //int _id = obj.GetInt("id");
    //char _discord[18];
    //float _elo = obj.GetFloat("elo");
    float _rws = obj.GetFloat("rws");
    int _rounds_total = obj.GetInt("rounds_total");

    // then apply the values to our local cache
    this.rws = _rws;
    this.rounds_total = _rounds_total;

    // Done. Set on_db and Return success
    this.on_db = true;
    return true;
  }

  // if steam auth and name are set, then this can be called to load a user from the database
  /*bool LoadData() {
    if (this.id != 0) {
      //load using database id method instead

      //after loading and success return true
      //this.on_db = true;
      return true;
    } else {
      //load using steamid lookup/init method
      if(!StrEqual(this.steamid2, "", false) && !StrEqual("BOT", this.steamid2, false) && !StrEqual("GOTV", this.steamid2, false)) {
        //this.on_db = true;
        return true;
      } else {
        //this.on_db = false;
        return false;
      }
    }
  }*/
}

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


// Global Forwards

/**
 * Called when a client issues a .help command in chat.
 *
 * @param client The client issuing the command
 * @param replyMessages An ArrayList of Strings to reply with (in chat)
 * @param maxMessageSize The max length of a string in the replyMessages list
 * @param block Whether to block the reply message (set to true to have no reply)
 */
forward void SegfaultRanks_OnHelpCommand(int client, ArrayList replyMessages, int maxMessageSize,
                                    bool& block);

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
}
#endif
