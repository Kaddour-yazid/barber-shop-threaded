extends Node

enum GameMode { NONE = -1, MANUAL = 0, AUTO = 1 }

var game_mode: int = GameMode.NONE
var seat_count: int = 4

var use_auto: bool:
	get:
		return game_mode == GameMode.AUTO
