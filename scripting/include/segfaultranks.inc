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

  void Remove() {
    this.on_db = false;

    this.id = 0;
    this.display_name = "NONAME";
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
// NONE

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
