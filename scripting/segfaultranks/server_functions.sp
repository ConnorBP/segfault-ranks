
//#define BASE_API_URL "http://localhost:1337/v1"
#define BASE_API_URL baseApiUrl
#define NEW_ROUND "newround"
#define USER_INIT "userinit"
#define GET_LEADERBOARD "leaderboard"

// https://github.com/clugg/sm-json
// this is where our json encoding results will go if we use decide to use the encoding features
//char jsonOutputCache[1024];

//Data required for submitting new round:
/*
pub struct RoundData {
    steam_id: String,
    did_win: bool,
    round_points: i32,
    team_points: i32,
    team_count: i32,
}
*/

/*

// Gets user stats from db using steamid and name, and initiates user if they don't already exist on db
void InitDbClientBySteam(int client) {
    if (GetFeatureStatus(FeatureType_Native, "SteamWorks_CreateHTTPRequest") == FeatureStatus_Available) {
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
        LogError("You must have either the SteamWorks extension installed to run segfaultranks");
        SetFailState("Cannot start segfault stats without steamworks extension.");
    }
}

// if the user already has a known database id, then we can easily refresh their stats with this
void LoadDbClientById(int client) {

}*/

// Sends a steam id and name to the server, if it exists it returns the stats to our callback, if not it creats a new user on the db and returns its new stats
bool InitUser(int client) {
    char url[128];
    Format(url, sizeof(url), "%s/%s", BASE_API_URL, USER_INIT);

    Handle initRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, url);
    if (initRequest == INVALID_HANDLE) {
        LogError("Failed to create HTTP request using url: %s", url);
        return false;
    }

    SteamWorks_SetHTTPCallbacks(initRequest, SteamWorks_OnUserReceived);
    SteamWorks_SetHTTPRequestContextValue(initRequest, GetClientSerial(client));
    SteamWorks_SetHTTPRequestGetOrPostParameter(initRequest, "steam_id", userData[client].steamid2);
    SteamWorks_SetHTTPRequestGetOrPostParameter(initRequest, "display_name", userData[client].display_name);

    /*
    Triggers a HTTPRequestCompleted_t callback.
    Returns true upon successfully setting the parameter.
    Returns false under the following conditions:
    hRequest was invalid.
    The request has already been sent.
    pCallHandle is NULL.
    */
    return SteamWorks_SendHTTPRequest(initRequest);
}

// Submits a round to the server. Returns true regardless of if the round actually updates on the server. Returns false if some failure happens trying to send it.
// actual handling of if the submission was successful is on the callback function
bool SendNewRound(int client, bool did_win, int round_points, int team_points, int team_count, int total_points, int total_count) {
    char url[128];
    Format(url, sizeof(url), "%s/%s", BASE_API_URL, NEW_ROUND);

    Handle authRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, url);
    if (authRequest == INVALID_HANDLE) {
        LogError("Failed to create HTTP request using url: %s", url);
        return false;
    }

    SteamWorks_SetHTTPCallbacks(authRequest, SteamWorks_OnNewRoundSent);
    SteamWorks_SetHTTPRequestContextValue(authRequest, GetClientSerial(client));
    SteamWorks_SetHTTPRequestGetOrPostParameter(authRequest, "steam_id", userData[client].steamid2);
    if(did_win) {
        //hacky boolToStr cause fuck sourcepawn
        SteamWorks_SetHTTPRequestGetOrPostParameter(authRequest, "did_win", "true");
    } else {
        SteamWorks_SetHTTPRequestGetOrPostParameter(authRequest, "did_win", "false");
    }
    char strRoundPoints[32];
    IntToString(round_points, strRoundPoints, sizeof(strRoundPoints));
    SteamWorks_SetHTTPRequestGetOrPostParameter(authRequest, "round_points", strRoundPoints);

    char strTeamPoints[32];
    IntToString(team_points, strTeamPoints, sizeof(strTeamPoints));
    SteamWorks_SetHTTPRequestGetOrPostParameter(authRequest, "team_points", strTeamPoints);
    char strTeamCount[32];
    IntToString(team_count, strTeamCount, sizeof(strTeamCount));
    SteamWorks_SetHTTPRequestGetOrPostParameter(authRequest, "team_count", strTeamCount);

    char strTotalPoints[32];
    IntToString(total_points, strTotalPoints, sizeof(strTotalPoints));
    SteamWorks_SetHTTPRequestGetOrPostParameter(authRequest, "total_points", strTotalPoints);
    char strTotalCount[32];
    IntToString(total_count, strTotalCount, sizeof(strTotalCount));
    SteamWorks_SetHTTPRequestGetOrPostParameter(authRequest, "total_count", strTotalCount);

    /*
    Triggers a HTTPRequestCompleted_t callback.
    Returns true upon successfully setting the parameter.
    Returns false under the following conditions:
    hRequest was invalid.
    The request has already been sent.
    pCallHandle is NULL.
    */
    return SteamWorks_SendHTTPRequest(authRequest);
}

bool GetLeaderboardData(int minRounds) {
    char url[128];
    Format(url, sizeof(url), "%s/%s/%i", BASE_API_URL, GET_LEADERBOARD, minRounds);

    Handle initRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, url);
    if (initRequest == INVALID_HANDLE) {
        LogError("Failed to create HTTP request using url: %s", url);
        return false;
    }

    SteamWorks_SetHTTPCallbacks(initRequest, SteamWorks_OnLeaderboardReceived);

    return SteamWorks_SendHTTPRequest(initRequest);
}


// Callback functions


// SteamWorksHTTPRequestCompleted 
// void (Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, any data1, any data2)
public void SteamWorks_OnUserReceived(Handle request, bool failure, bool requestSuccessful, EHTTPStatusCode statusCode, int serial) {
    if (failure || !requestSuccessful) {
        LogError("API request failed, HTTP status code = %d", statusCode);
        return;
    }

    int size;
    if(SteamWorks_GetHTTPResponseBodySize(request, size)) {
        if(size>0) {
            char[] responseBody = new char[size];
            SteamWorks_GetHTTPResponseBodyData(request, responseBody, size);

            if (statusCode == k_EHTTPStatusCode200OK) {
                if (serial != 0) {
                    int client = GetClientFromSerial(serial);
                    PrintToServer("Client %i was successfully loaded in the database!", client);
                    PrintToServer("Got response: %s", responseBody);//temporary

                    // parse the received data into the appropriate client storage
                    if(userData[client].ParseFromJson(responseBody, true)) {
                        PrintToServer("Client %i data was successfully parsed into local cache!", client);
                        // apply rws to scoreboard
                        if(IsPlayer(client)) {
                            SetClientRwsDisplay(client, userData[client].rws);
                        }
                    } else {
                        LogError("Failed to parse user init json from response body: %s", responseBody);
                    }
                    // set on_db to true here even if setting the local variables fails for now just in case an initially empty stat breaks the json decoder.
                    // users don't get rounds submitted until this is set to confirm they are initialized on the database
                    //userData[client].on_db = true;//disabled, gets set inside of ParseFromJson
                
                }
            } 
            else {
                LogError("Bad Status code: %i Response: %s", statusCode, responseBody);
            }
        } else {
            LogError("The response body was empty while retreiving the user.");
        }
    } else {
        LogError("There was a problem trying to retreive the size of the response body.");
    }
}

public void SteamWorks_OnNewRoundSent(Handle request, bool failure, bool requestSuccessful, EHTTPStatusCode statusCode, int serial) {
    if (failure || !requestSuccessful) {
        LogError("API request failed, HTTP status code = %d", statusCode);
        return;
    }

    int size;
    if(SteamWorks_GetHTTPResponseBodySize(request, size)) {
        if(size>0) {
            char[] responseBody = new char[size];
            SteamWorks_GetHTTPResponseBodyData(request, responseBody, size);

            if (statusCode == k_EHTTPStatusCode200OK) {
                if (serial != 0) {
                    int client = GetClientFromSerial(serial);
                    PrintToServer("New round successfully sent for client: %i", client);
                    PrintToServer("Got response: %s", responseBody);//temporary
                    // update stats from returned values with init mode disabled since we already initiated the user
                    if(IsPlayer(client)) {
                        if(userData[client].ParseFromJson(responseBody, false)) {
                            // apply rws to scoreboard
                            SetClientRwsDisplay(client, userData[client].rws);
                        } else {
                            LogError("Failed to parse user init json from response body: %s", responseBody);
                        }
                    } else {
                        LogError("Client %i was not a valid player in newround callback. Response: %s", client, responseBody);
                    }
                }
            } 
            else {
                LogError("Bad Status code: %i Error message: %s", statusCode, responseBody);
            }
        } else {
            LogError("The response body was empty while sending a new round.");
        }
    } else {
        LogError("There was a problem trying to retreive the size of the response body in NewRoundSent callback.");
    }

}

public void SteamWorks_OnLeaderboardReceived(Handle request, bool failure, bool requestSuccessful, EHTTPStatusCode statusCode) {
    if (failure || !requestSuccessful) {
        LogError("API request failed, HTTP status code = %d", statusCode);
        return;
    }

    int size;
    if(SteamWorks_GetHTTPResponseBodySize(request, size)) {
        if(size>0) {
            char[] responseBody = new char[size];
            SteamWorks_GetHTTPResponseBodyData(request, responseBody, size);

            if (statusCode == k_EHTTPStatusCode200OK) {

                PrintToServer("Got response: %s", responseBody);//temporary

                // parse the received data into the appropriate client storage
                ParseLeaderboardDataIntoCache(responseBody, topTenLeaderboard, 10);
                PrintToServer("Leaderboard data was successfully parsed into local cache!");
 
            } 
            else {
                LogError("Bad Status code: %i Response: %s", statusCode, responseBody);
            }
        } else {
            LogError("The response body was empty while retreiving the user.");
        }
    } else {
        LogError("There was a problem trying to retreive the size of the response body.");
    }
}