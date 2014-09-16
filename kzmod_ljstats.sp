#pragma semicolon 1

public Plugin:myinfo = 
{
    name = "KZmod LJ Stats",
    author = "Aoki",
    description = "Longjump stats",
    version = "0.1.2",
    url = "http://www.kzmod.com/"
}

//-------------------------------------------------------------------------
// Includes
//-------------------------------------------------------------------------
#include <sourcemod>
#include <sdktools>

//-------------------------------------------------------------------------
// Defines 
//-------------------------------------------------------------------------
#define LOG_DEBUG_ENABLE 0
#define LOG_TO_CHAT 1
#define LOG_TO_SERVER 1

#define MIN_BH_LJ_TICKS 44
#define MIN_LJ_TICKS 65
#define MAX_LJ_TICKS 75

#define MAX_STRAFES 15

#define EYE_YAW_IDX (1)
#define EYE_YAW_DELTA_STAFE_MIN (0.01)

#define RESET_DUCK_COUNT_TICKS (40)

//-------------------------------------------------------------------------
// Types 
//-------------------------------------------------------------------------
enum teStrafeDir (+= 1)
{
	eeStrafeNone = 0,
	eeStrafeLeft,
	eeStrafeRight,
	eeStrafeBoth
};

enum teJumpType (+= 1)
{
	eeLj = 0,
	eeCj,
	eeDcj,
	eeMcj,
	eeBhopLj
};

//-------------------------------------------------------------------------
// Globals 
//-------------------------------------------------------------------------
new gnTick = 0;
new bool:gaePlayerInJump[MAXPLAYERS+1] = { false, ... };
new ganLastDuckTick[MAXPLAYERS+1] = { 0, ... };
new String:gpaanPlayerName[MAXPLAYERS+1][MAX_NAME_LENGTH+1];
new bool:gaeShowStats[MAXPLAYERS+1] = { false, ... };

//Per tick data
new ganButtons[MAXPLAYERS+1] = { 0, ... };
new ganFlags[MAXPLAYERS+1] = { 0, ... };
new ganPrevButtons[MAXPLAYERS+1] = { 0, ... };
new ganPrevFlags[MAXPLAYERS+1] = { 0, ... };

//Per jump data
new ganStrafeCount[MAXPLAYERS+1];
new ganStartJumpTick[MAXPLAYERS+1];
new Float:gaarStartJumpPos[MAXPLAYERS+1][3];
new Float:garPreStrafe[MAXPLAYERS+1];
new Float:garPrevVel[MAXPLAYERS+1];
new ganDuckCount[MAXPLAYERS+1] = { 0, ... };
new ganBhopCount[MAXPLAYERS+1] = { 0, ... };
new gnTicksOnGround[MAXPLAYERS+1] = { 0, ... };

//Strafe data
new teStrafeDir:gaeThisStrafeDir[MAXPLAYERS+1];
new teStrafeDir:gaePrevStrafeDir[MAXPLAYERS+1];
new Float:gaarGain[MAXPLAYERS+1][MAX_STRAFES];
new Float:gaarLoss[MAXPLAYERS+1][MAX_STRAFES];
new gaanStrafeTicks[MAXPLAYERS+1][MAX_STRAFES];
new gaanGoodSyncTicks[MAXPLAYERS+1][MAX_STRAFES];
new gaanBadSyncTicks[MAXPLAYERS+1][MAX_STRAFES];

//-------------------------------------------------------------------------
// Functions 
//-------------------------------------------------------------------------
public LogDebug(const String:aapanFormat[], any:...)
{
#if LOG_DEBUG_ENABLE == 1
	decl String:ppanBuffer[512];
	
	VFormat(ppanBuffer, sizeof(ppanBuffer), aapanFormat, 2);
#if LOG_TO_CHAT == 1
	PrintToChatAll("%s", ppanBuffer);
#endif
#if LOG_TO_SERVER == 1
	PrintToServer("%s", ppanBuffer);
#endif
#endif
}

public OnGameFrame()
{
	gnTick++;
	
	if(gnTick < 0)
	{
		gnTick = 0;
	}
}
	
public OnPluginStart()
{
	RegConsoleCmd("sm_lj", cbLjToggle, "Toggle LJ stat display");

	//TODO
	HookEvent("player_stats_readout",ev_StatsReadout,EventHookMode_Post);
	HookEvent("player_jump",ev_PlayerJump,EventHookMode_Post);
	
	AddCommandListener(cbOnClientNameChange, "name");
	
	for(new lnClient=1;lnClient<MaxClients;lnClient++)
	{
		if(IsClientConnected(lnClient) && IsClientAuthorized(lnClient))
		{
			GetClientName(lnClient, gpaanPlayerName[lnClient], MAX_NAME_LENGTH+1);
		}
	}
}

public Action:cbLjToggle(anClient, ahArgs)
{
	gaeShowStats[anClient] = !gaeShowStats[anClient];
	
	if(gaeShowStats[anClient])
	{
		PrintToChat(anClient,"\x04[LJ]\x03 Stats enabled");
	}
	else
	{
		PrintToChat(anClient,"\x04[LJ]\x03 Stats disabled");
	}
}

public OnClientAuthorized(anClient, const String:apanAuth[])
{
	GetClientName(anClient, gpaanPlayerName[anClient], MAX_NAME_LENGTH+1);
}

public Action:cbOnClientNameChange(anClient, const String:apanCommand[], anArgc)
{
	GetClientName(anClient, gpaanPlayerName[anClient], MAX_NAME_LENGTH+1);
}

public OnClientDisconnect_Post(anClient)
{
	gaeShowStats[anClient] = false;
}

public OnMapStart()
{
	//TODO
}

public Action:OnPlayerRunCmd(anClient, &apButtons, &apImpulse, Float:arVel[3], Float:arAngles[3], &apWeapon)
{
	if(IsPlayerAlive(anClient) && gaeShowStats[anClient] == true)
	{
		ganButtons[anClient] = apButtons;
		ganFlags[anClient] = GetEntityFlags(anClient);
		
		if(gaePlayerInJump[anClient] == false)
		{
			if(ganFlags[anClient]&FL_ONGROUND == 0 && ganPrevFlags[anClient]&FL_ONGROUND)
			{
				ganDuckCount[anClient]++;
			
				ganLastDuckTick[anClient] = gnTick;
			}
			
			if(ganDuckCount[anClient] > 0 && ganFlags[anClient]&FL_ONGROUND &&
				gnTick - ganLastDuckTick[anClient] > RESET_DUCK_COUNT_TICKS)
			{
				ganDuckCount[anClient] = 0;
			}
		}
		
		if(ganFlags[anClient]&FL_ONGROUND)
		{
			gnTicksOnGround[anClient]++;
			
			if(gnTicksOnGround[anClient] > 5) //TODO
			{
				ganBhopCount[anClient] = 0;
			}
		}
		else
		{
			gnTicksOnGround[anClient] = 0;
		}
		
		//If player is landing a jump (on ground this tick but not the last)
		if(ganFlags[anClient]&FL_ONGROUND && ganPrevFlags[anClient]&FL_ONGROUND == 0 &&
		   gaePlayerInJump[anClient] == true)
		{
			new lnJumpTicks = gnTick - ganStartJumpTick[anClient];
			
			if(ganBhopCount[anClient] < 2 && lnJumpTicks > MIN_BH_LJ_TICKS && 
			   lnJumpTicks < MAX_LJ_TICKS)
			{
				ProcessJumpStats(anClient);
			}
			
			ResetClientGlobals(anClient);
		}
		//Else if the player is in a jump
		else if(gaePlayerInJump[anClient] == true)
		{
			ProcessStrafeData(anClient);
		}
		
		ganPrevButtons[anClient] = ganButtons[anClient];
		ganPrevFlags[anClient] = ganFlags[anClient];
	}
}

ProcessStrafeData(anClient)
{
	new lnStrafeIndex;
	new Float:lrVelDelta;
	gaeThisStrafeDir[anClient] = GetPlayerMoveStrafeDir(anClient);
	
	if(IsNewStrafe(anClient) == true && ganStrafeCount[anClient] < MAX_STRAFES)
	{	
		gaePrevStrafeDir[anClient] = gaeThisStrafeDir[anClient];
		gaarGain[anClient][ganStrafeCount[anClient]] = 0.0;
		gaarLoss[anClient][ganStrafeCount[anClient]] = 0.0;
		gaanStrafeTicks[anClient][ganStrafeCount[anClient]] = 0;
		gaanGoodSyncTicks[anClient][ganStrafeCount[anClient]] = 0;
		gaanBadSyncTicks[anClient][ganStrafeCount[anClient]] = 0;
		ganStrafeCount[anClient]++;
	}
	
	lnStrafeIndex = ganStrafeCount[anClient] - 1;
	
	if(lnStrafeIndex >= 0 && lnStrafeIndex < MAX_STRAFES)
	{
		lrVelDelta = CalculateGainsAndLosses(anClient,lnStrafeIndex);
		CalculateSync(anClient,lnStrafeIndex,lrVelDelta);
	}
}

CalculateSync(anClient,anStrafeIndex,Float:arVelocityDelta)
{
	gaanStrafeTicks[anClient][anStrafeIndex]++;

	//If not holding two opposite directions at once
	if(!(ganButtons[anClient]&IN_MOVELEFT) || !(ganButtons[anClient]&IN_MOVERIGHT) &&
	   !(ganButtons[anClient]&IN_FORWARD) || !(ganButtons[anClient]&IN_BACK))
	{
		if(arVelocityDelta > 0.0)
		{
			gaanGoodSyncTicks[anClient][anStrafeIndex]++;
		}
		else if(arVelocityDelta < 0.0)
		{
			gaanBadSyncTicks[anClient][anStrafeIndex]++;
		}
	}
}

Float:CalculateGainsAndLosses(anClient,anStrafeIndex)
{
	new Float:lrXyVel = GetPlayerXYVel(anClient);
	new Float:lrDelta = 0.0;
	
	if(ganButtons[anClient]&IN_MOVELEFT || ganButtons[anClient]&IN_MOVERIGHT)
	{
		lrDelta = lrXyVel - garPrevVel[anClient];
	
		if(lrDelta > 0.0)
		{
			gaarGain[anClient][anStrafeIndex] += lrDelta;
		}
		else if(lrDelta < 0.0)
		{
			gaarLoss[anClient][anStrafeIndex] += -lrDelta;
		}
	}
	
	garPrevVel[anClient]= lrXyVel;
	
	return lrDelta;
}

bool:IsNewStrafe(anClient)
{
	new bool:leIsNewStrafe = false;
	
	if(ganStrafeCount[anClient] == 0 && 
	   (gaeThisStrafeDir[anClient] == eeStrafeLeft || gaeThisStrafeDir[anClient] == eeStrafeRight))
	{
		leIsNewStrafe = true;
	}
	if(gaeThisStrafeDir[anClient] == eeStrafeLeft && gaePrevStrafeDir[anClient] == eeStrafeRight)
	{
		leIsNewStrafe = true;
	}
	else if(gaeThisStrafeDir[anClient] == eeStrafeRight && gaePrevStrafeDir[anClient] == eeStrafeLeft)
	{
		leIsNewStrafe = true;
	}
	
	return leIsNewStrafe;
}

static Float:GetPlayerXYVel(anClient)
{
	new Float:larVel[3];
	
	GetEntPropVector(anClient, Prop_Data, "m_vecVelocity", larVel);
	larVel[2] = 0.0;
	return GetVectorLength(larVel);
}

public Action:ev_PlayerJump(Handle:ahEvent, String:apanName[], bool:aeDontBroadcast)
{
	new lnClient = GetClientOfUserId(GetEventInt(ahEvent, "userid"));
	
	if(gaeShowStats[lnClient] == true)
	{
		new lnTicksSinceLastJump = gnTick - ganStartJumpTick[lnClient];
		
		//Check if this is a bhop jump
		if(lnTicksSinceLastJump > MIN_BH_LJ_TICKS && lnTicksSinceLastJump < MAX_LJ_TICKS)
		{
			new Float:larNewJumpPos[3];
			GetEntPropVector(lnClient, Prop_Send, "m_vecOrigin",larNewJumpPos);
			
			//Only count as a bhop if z pos isn't changing
			if(FloatAbs(larNewJumpPos[2] - ganStartJumpTick[2]) > 0.001)
			{
				ganBhopCount[lnClient]++;
			}
		}

		GetEntPropVector(lnClient, Prop_Send, "m_vecOrigin", gaarStartJumpPos[lnClient]);
		ganStartJumpTick[lnClient] = gnTick;
		garPreStrafe[lnClient] = GetPlayerXYVel(lnClient);
		garPrevVel[lnClient] = garPreStrafe[lnClient];
		gaePlayerInJump[lnClient] = true;
	}
}

Float:CalculateJumpDistance(anClient,Float:aarStart[3],Float:aarEnd[3])
{
	if(ganFlags[anClient]&FL_DUCKING)
	{
		return GetVectorDistance(aarStart,aarEnd) + 32.67;
	}
	else
	{
		return GetVectorDistance(aarStart,aarEnd) + 32.3;
	}
}

ProcessJumpStats(anClient)
{
	new Float:larEndPos[3];
	GetEntPropVector(anClient, Prop_Send, "m_vecOrigin", larEndPos);
	decl String:ppanText[64];
	new Float:lrAvgSync = 0.0;
	new Float: lrSync = 0.0;
	
	new Float:lrJumpDist = CalculateJumpDistance(anClient,gaarStartJumpPos[anClient],larEndPos);
	
	//TODO
	if(FloatAbs(gaarStartJumpPos[anClient][2] - larEndPos[2]) > 0.001)
	{
		return;
	}
	else if(ganBhopCount[anClient] > 0 && lrJumpDist < 200.0)
	{
		return;
	}
	else if(lrJumpDist < 220.0)
	{
		return;
	}
	
	new Handle:lhPanel = CreatePanel();
	SetPanelTitle(lhPanel, "#   Gain    Loss   Sync");
	SetPanelKeys(lhPanel,0xFFFFFFFF);
	
	for(new lnStrafe=0;lnStrafe<ganStrafeCount[anClient];lnStrafe++)
	{
		lrSync = float(gaanGoodSyncTicks[anClient][lnStrafe]) / 
			float(gaanStrafeTicks[anClient][lnStrafe]) * 100.0;
		
		lrAvgSync += lrSync;
		
		Format(ppanText,sizeof(ppanText),"%2i  %05.2f  %05.2f  %3.0f",
			lnStrafe+1,
			gaarGain[anClient][lnStrafe],
			gaarLoss[anClient][lnStrafe],
			lrSync);

		PrintToConsole(anClient,"%s",ppanText);
					
		DrawPanelText(lhPanel,ppanText);
	}
	
	lrAvgSync = lrAvgSync / float(ganStrafeCount[anClient]);
	
	PrintJumpToChat(anClient,lrJumpDist,lrAvgSync);
	
	SendPanelToClient(lhPanel, anClient, cbTimeLeftPanelHandler, 10);
	CloseHandle(lhPanel);
}

PrintJumpToChat(anClient,Float:arJumpDist,Float:arAvgSync)
{
	if(ganBhopCount[anClient] > 0) //bhop lj
	{
		PrintToChat(anClient,"\x04[BHLJ]\x03 %3.2f units, pre %3.1f, %d strafes, %3.0f sync",
			arJumpDist,garPreStrafe[anClient],ganStrafeCount[anClient],arAvgSync);
	}
	else if(ganDuckCount[anClient] == 0) //normal lj
	{
		PrintToChat(anClient,"\x04[LJ]\x03 %3.2f units, pre %3.1f, %d strafes, %3.0f sync",
			arJumpDist,garPreStrafe[anClient],ganStrafeCount[anClient],arAvgSync);
	}
	else if(ganDuckCount[anClient] == 1)
	{
		PrintToChat(anClient,"\x04[CJ]\x03 %3.2f units, pre %3.1f, %d strafes, %3.0f sync",
			arJumpDist,garPreStrafe[anClient],ganStrafeCount[anClient],arAvgSync);
	}
	else if(ganDuckCount[anClient] == 2)
	{
		PrintToChat(anClient,"\x04[DCJ]\x03 %3.2f units, pre %3.1f, %d strafes, %3.0f sync",
			arJumpDist,garPreStrafe[anClient],ganStrafeCount[anClient],arAvgSync);
	}
	else if(ganDuckCount[anClient] > 2)
	{
		PrintToChat(anClient,"\x04[MCJ]\x03 %3.2f units, pre %3.1f, %d strafes, %3.0f sync, %i ducks",
			arJumpDist,garPreStrafe[anClient],ganStrafeCount[anClient],arAvgSync,ganDuckCount[anClient]);
	}
}

public cbTimeLeftPanelHandler(Handle:ahMenu, MenuAction:ahAction, anClient, anSelect)
{
	if (ahAction == MenuAction_Select)
	{
	}
	else if (ahAction == MenuAction_Cancel)
	{
	}
}

teStrafeDir:GetPlayerMoveStrafeDir(anClient)
{
	if(ganButtons[anClient]&IN_MOVELEFT && ganButtons[anClient]&IN_MOVERIGHT)
	{
		return eeStrafeBoth;
	}
	else if(ganButtons[anClient]&IN_MOVELEFT)
	{
		return eeStrafeLeft;
	}
	else if(ganButtons[anClient]&IN_MOVERIGHT)
	{
		return eeStrafeRight;
	}
	else
	{
		return eeStrafeNone;
	}
}

public ResetClientGlobals(anClient)
{
	gaePlayerInJump[anClient] = false;
	ganStrafeCount[anClient] = 0;
	gaeThisStrafeDir[anClient] = eeStrafeNone;
	gaePrevStrafeDir[anClient] = eeStrafeNone;
	ganDuckCount[anClient] = 0;
}

public ev_StatsReadout(Handle:ahEvent,const String:apanEventName[],bool:aeDontBroadcast)
{
	//"userid" "short"
	//"jump_distance"	"float"
	//"prestrafe"	"float"
	//"max_speed"	"float"
	//"consecutive_bhops" "short"
	
	//new lnUserId = GetEventInt(ahEvent, "userid");
	//new Float:lrJumpDist = GetEventFloat(ahEvent, "jump_distance");
	//new Float:lrPrestrafe = GetEventFloat(ahEvent, "prestrafe");
	//new Float:lrMaxSpeed = GetEventFloat(ahEvent, "max_speed");
	//new lnBhops = GetEventInt(ahEvent, "consecutive_bhops");
	
	//LogDebug("user=%i,dist=%f,pre=%f,max=%f,bh=%i",lnUserId,lrJumpDist,lrPrestrafe,lrMaxSpeed,lnBhops);
}


