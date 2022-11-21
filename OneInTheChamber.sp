#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "Diam0ndz"
#define PLUGIN_VERSION "1.0"

#define WEAPON_NAME_LEN 32
#define WIN_MULTIPLIER 1000
#define KILL_MULTIPLIER 100

/* Default includes */
#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <sdkhooks>

/* Includes that I put in */
#include "include/nextmap.inc"

#pragma newdecls required

EngineVersion g_Game;

ConVar oitc_maxRounds;
ConVar oitc_maxPoints;
ConVar oitc_weapon;

int Points[MAXPLAYERS + 1];
int Wins[MAXPLAYERS + 1];
int Round;

enum struct HitData {
    int attackerId;
    int hits;
}

HitData multihit[MAXPLAYERS + 1];

/* Plugin info */
public Plugin myinfo =
{
    name = "One In The Chamber",
    author = PLUGIN_AUTHOR,
    description = "One shot, one kill. Waste your bullet and you have to knife someone to get it back.",
    version = PLUGIN_VERSION,
    url = "https://steamcommunity.com/id/Diam0ndz/"
};

public void OnPluginStart()
{
    g_Game = GetEngineVersion();
    if(g_Game != Engine_CSGO && g_Game != Engine_CSS)
    {
        SetFailState("This plugin is for CSGO/CSS only.");
    }

    oitc_maxPoints = CreateConVar("oitc_maxpoints", "25", "The maximum amount of points to gain before winning the game");
    oitc_maxRounds = CreateConVar("oitc_maxrounds", "3", "The maximum amount of rounds before switching the map");
    oitc_weapon = CreateConVar("oitc_weapon", "weapon_tec9", "The weapon to use for gameplay");

    HookEvent("player_spawned", Event_PlayerSpawned); //Different events to hook
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("round_poststart", Event_RoundPostStart);
    HookEvent("player_hurt", Event_PlayerHurt);

    //RegAdminCmd("sm_setpoints", SetPoints, ADMFLAG_ROOT, "Set the points of a client in the One in the Chamber plugin");
    RegConsoleCmd("sm_setpoints", SetPoints, "Set the points of a client in the One in the Chamber plugin", ADMFLAG_ROOT);

    AutoExecConfig(true, "oitc", _);
}

public void OnMapStart()
{
    ServerCommand("mp_randomspawn 1"); //Different server commands optimal for One in the Chamber
    ServerCommand("mp_death_drop_gun 0");
    ServerCommand("mp_death_drop_defuser 0");
    ServerCommand("mp_death_drop_grenade 0");
    ServerCommand("mp_freezetime 2");
    ServerCommand("mp_warmuptime 0");
    ServerCommand("mp_do_warmup_period 0");
    ServerCommand("mp_teammates_are_enemies 1");
    ServerCommand("mp_ignore_round_win_conditions 1");
    ServerCommand("mp_roundtime 5");
    ServerCommand("mp_timelimit 10");
    ServerCommand("mp_join_grace_time 300"); // roundtime * 60
    //mp_endmatch_votenextmap
    ServerCommand("mp_maxrounds %i", GetConVarInt(oitc_maxRounds));
}

public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage); //Hook when you take damage
    Points[client] = 0; //Set points to 0
    Wins[client] = 0;
    Round = 1;
}

public Action Event_RoundPostStart(Event event, const char[] name, bool dontBroadcast)
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsValidClient(i))
        {
            StripAndGive(i, 0);
            Points[i] = 0;
            CS_SetClientContributionScore(i, 0);
        }
    }
    return Plugin_Continue;
}

public Action Event_PlayerSpawned(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(GetEventInt(event, "userid"));
    StripAndGive(client, 0);
    return Plugin_Continue;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(GetEventInt(event, "userid"));
    CreateTimer(0.5, RespawnClient, client);
    return Plugin_Continue;
}

public Action Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
    int attackerid = GetEventInt(event, "attacker");
    int attacker = GetClientOfUserId(attackerid);
    char weaponName[WEAPON_NAME_LEN];
    GetEventString(event, "weapon", weaponName, sizeof(weaponName), "");
    SetEventInt(event, "health", 0);
    if (StrEqual(weaponName, "knife")) {
        StripAndGive(attacker, 1);
    } else {
        // The player was shot, see if it's a multihit
        if(multihit[attacker].attackerId == 0)
        {
            RequestFrame(Frame_Multihit, attacker);
            multihit[attacker].attackerId = attackerid;
            multihit[attacker].hits = 0;
        }
        multihit[attacker].hits += 1;
    }
    Points[attacker] += 1;
    CS_SetClientContributionScore(attacker, Points[attacker] * KILL_MULTIPLIER);
    if(Points[attacker] >= GetConVarInt(oitc_maxPoints))
    {
        RequestFrame(Frame_PlayerHurt, attackerid);
    }
    else
    {
        PrintHintText(attacker, "Points : %i/%i", Points[attacker], GetConVarInt(oitc_maxPoints));
    }
    return Plugin_Continue;
}

public Action SetPoints(int client, int args)
{
    if (args < 1 || args > 2)
    {
        ReplyToCommand(client, "Usage: sm_setpoints <name> <points(0-24)>");
        return Plugin_Handled;
    }
    char name[32];
    int target = -1;
    GetCmdArg(1, name, sizeof(name));

    for (int i = 1; i <= MaxClients; i++)
    {
        if(!IsClientConnected(i))
        {
            continue;
        }
        char other[32];
        GetClientName(i, other, sizeof(other));
        if(StrEqual(name, other))
        {
            target = i;
        }
    }

    if(target == -1)
    {
        ReplyToCommand(client, "No player found with username %s", name);
        return Plugin_Handled;
    }

    char pointsToGive[32];
    int pointNum = -1;
    GetCmdArg(2, pointsToGive, sizeof(pointsToGive));
    pointNum = StringToInt(pointsToGive);
    if(pointNum > GetConVarInt(oitc_maxPoints) - 1 || pointNum < 0)
    {
        ReplyToCommand(client, "Point value must be between 0 and 24!");
        return Plugin_Handled;
    }
    Points[target] = pointNum;
    PrintToChatAll(" \x06%N \x0Bset \x06%N's \x0Bpoints to \x06%i", client, target, pointNum);
    return Plugin_Handled;
}

public void Frame_Multihit(int data)
{
    if (multihit[data].attackerId == 0) {
        multihit[data].hits = 0;
        return;
    }

    if (multihit[data].hits < 1) {
        PrintToServer("[OITC] player didn't hit anyone?!");
        multihit[data].attackerId = 0;
        multihit[data].hits = 0;
        return;
    }

    // Get the attacker to make sure they're still in game
    int attacker = GetClientOfUserId(multihit[data].attackerId);

    if (attacker > 0 && IsClientInGame(attacker)) {
        StripAndGive(attacker, multihit[data].hits);
    }
    multihit[data].attackerId = 0;
    multihit[data].hits = 0;
}

public void Frame_PlayerHurt(int userid)
{
    int attacker = GetClientOfUserId(userid);

    if (attacker > 0 && IsClientInGame(attacker))
    {
        PlayerWon(attacker);
    }
}

stock void PlayerWon(int client)
{
    PrintToChatAll(" \x06%N \x0Bwon with \x06%i \x0Bpoints !", client, Points[client]);
    PrintCenterTextAll(" \x06%N \x0Bwon with \x06%i \x0Bpoints !", client, Points[client]);
    CSRoundEndReason reason = CSRoundEnd_Draw;
    int team = GetClientTeam(client);
    if (team == CS_TEAM_T) {
        reason = CSRoundEnd_TerroristWin;
    } else if (team == CS_TEAM_CT) {
        reason = CSRoundEnd_CTWin;
    }
    Wins[client] += 1;

    if(Round < GetConVarInt(oitc_maxRounds))
    {
        CS_TerminateRound(2.0, reason, true);
        Round += 1;
        Points[client] = 0;
        PrintToChatAll(" \x0BCurrently starting round \x06%i \x0Bout of round \x06%i", Round, GetConVarInt(oitc_maxRounds));
    }
    else
    {
        for (int i = 1; i <= MaxClients; i++) {
            if (IsValidClient(i)) {
                CS_SetClientContributionScore(i, Wins[i] * WIN_MULTIPLIER);
                CS_SetMVPCount(i, Wins[i]);
            }
        }
        CS_TerminateRound(5.0, reason, true);
        PrintCenterTextAll("\x0BThe final round has ended!");
        SetConVarInt(FindConVar("mp_timelimit"), 0, false, false);
        SetConVarInt(FindConVar("mp_maxrounds"), 0, false, false);
    }
}

public Action CS_OnCSWeaponDrop(int client, int weapon)
{
    return Plugin_Handled;
}

public Action OnTakeDamage(int victim, int&attacker, int&inflictor, float&damage, int&damagetype, int&weapon, float damageForce[3], float damagePosition[3])
{
    if(IsValidClient(victim))
    {
        if(damagetype == DMG_FALL)
        {
            return Plugin_Handled;
        }
        if(weapon != 0)
        {
            damage = 500.0;
            return Plugin_Changed;
        }
    }
    return Plugin_Continue;
}

public void StripAndGive(int client, int newAmmo)
{
    int prevAmmo = StripWeapon(client, newAmmo > 0);

    if (newAmmo > 0)
    {
        prevAmmo += newAmmo;
    }
    else
    {
        prevAmmo = 1; // Give only 1 bullet
    }

    GiveWeapon(client, prevAmmo);
}

public void GiveWeapon(int client, int ammo)
{
    char weapon_name[WEAPON_NAME_LEN];
    oitc_weapon.GetString(weapon_name, sizeof(weapon_name));
    GivePlayerItem(client, weapon_name, 0);
    int weapon =  GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");
    SetAmmo(client, weapon, ammo);
    GivePlayerItem(client, "weapon_knife", 0);
}

public int StripWeapon(int client, bool getAmmo)
{
    int ammo = 0;
    int weapon = -1;
    if(client > 0 && IsClientInGame(client) && IsPlayerAlive(client) && GetClientTeam(client) > 1)
    {
        weapon = -1;
        for(int slot = 5; slot >= 0; slot--)
        {
            while((weapon = GetPlayerWeaponSlot(client, slot)) != -1)
            {
                if(IsValidEntity(weapon))
                {
                    if (getAmmo) {
                        char weaponName[WEAPON_NAME_LEN];
                        char weaponCvar[WEAPON_NAME_LEN];
                        GetEntityClassname(weapon, weaponName, sizeof(weaponName));
                        oitc_weapon.GetString(weaponCvar, sizeof(weaponCvar));
                        if (StrEqual(weaponName, weaponCvar)) {
                            ammo = GetClipAmmo(client, weapon);
                        }
                    }
                    RemovePlayerItem(client, weapon);
                }
            }
        }
    }
    return ammo;
}

public Action RespawnClient(Handle timer, int client)
{
    if (IsClientInGame(client)) {
        CS_RespawnPlayer(client);
        StripAndGive(client, 0);
    }
    return Plugin_Continue;
}

public void SetAmmo(int client, int weapon, int ammo)
{
  if (IsValidEntity(weapon)) {
    //Primary ammo
    SetReserveAmmo(client, weapon, 0);

    //Clip
    SetClipAmmo(client, weapon, ammo);
  }
}

public Action CS_OnBuyCommand(int client, const char[] weapon)
{
    return Plugin_Handled;
}

stock void SetReserveAmmo(int client, char weapon, int ammo)
{
  SetEntProp(weapon, Prop_Send, "m_iPrimaryReserveAmmoCount", ammo); //set reserve to 0

  int ammotype = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType");
  if(ammotype == -1) return;

  SetEntProp(client, Prop_Send, "m_iAmmo", ammo, _, ammotype);
}


stock void SetClipAmmo(int client, char weapon, int ammo)
{
  SetEntProp(weapon, Prop_Send, "m_iClip1", ammo);
  SetEntProp(weapon, Prop_Send, "m_iClip2", ammo); // m_iClip2 is only used for weapons that have 2 clips, i.e. HL2 grenade launcher SMG
}

stock int GetClipAmmo(int client, char weapon)
{
    return
        GetEntProp(weapon, Prop_Send, "m_iClip1", 1);
}

stock bool IsValidClient(int client)
{
    if (client <= 0) return false;
    if (client > MaxClients) return false;
    if (!IsClientConnected(client)) return false;
    return IsClientInGame(client);
}