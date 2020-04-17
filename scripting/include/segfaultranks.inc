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
  }

  void ResetStats() {
    this.elo = 0.0;
    this.rws = 0.0;

    this.rounds_total = 0;
    this.round_points = 0;
  }

  void ResetRound() {
    this.round_points = 0;
  }

  // if steam auth and name are set, then this can be called to load a user from the database
  bool LoadData() {
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
  }
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
