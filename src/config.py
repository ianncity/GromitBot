"""Configuration module for GromitBot."""

import json
import os
from pathlib import Path


class Config:
    """Configuration manager for the bot."""
    
    def __init__(self, config_file='config.json'):
        """Initialize the configuration."""
        self.config_file = config_file
        self.config = {}
        self._load_config()
        
    def _load_config(self):
        """Load configuration from file."""
        config_path = Path(self.config_file)
        
        if not config_path.exists():
            # Create default config
            self._create_default_config()
        else:
            with open(config_path, 'r') as f:
                self.config = json.load(f)
                
    def _create_default_config(self):
        """Create default configuration file."""
        default_config = {
            "general": {
                "log_level": "INFO",
                "save_state_interval": 60,
                "emergency_stop_key": "F9"
            },
            "discord": {
                "enabled": False,
                "token": "",
                "command_channel": "bot-commands",
                "allowed_users": []
            },
            "human_behavior": {
                "min_delay": 0.5,
                "max_delay": 2.0,
                "mouse_speed_min": 0.3,
                "mouse_speed_max": 1.2,
                "pause_chance": 0.1,
                "pause_duration_min": 2,
                "pause_duration_max": 8
            },
            "fishing": {
                "enabled": True,
                "cast_key": "1",
                "fishing_spot_colors": [[45, 100, 150], [50, 110, 160]],
                "loot_range": {
                    "min_x": 500,
                    "max_x": 900,
                    "min_y": 300,
                    "max_y": 600
                },
                "wait_time_min": 8000,
                "wait_time_max": 15000
            },
            "herbalism": {
                "enabled": True,
                "path_file": "paths/herbalism.json",
                "gather_key": "4",
                "herb_color_range": {
                    "min": [40, 120, 40],
                    "max": [80, 180, 80]
                },
                "scan_interval": 500
            },
            "leveling": {
                "enabled": False,
                "path_file": "paths/leveling.json",
                "combat_key": "1",
                "target_range": 30,
                "pull_distance": 40,
                "rest_threshold": 0.3,
                "food_key": "2",
                "drink_key": "3"
            },
            "inventory": {
                "enabled": True,
                "full_threshold": 14,
                "vendor_route": "paths/vendor.json",
                "sell_items": True,
                "auto_repair": True
            },
            "screen": {
                "game_window_title": "World of Warcraft",
                "capture_region": {
                    "x": 0,
                    "y": 0,
                    "width": 1920,
                    "height": 1080
                }
            }
        }
        
        with open(self.config_file, 'w') as f:
            json.dump(default_config, f, indent=4)
            
        self.config = default_config
        
    def get(self, key, default=None):
        """Get a configuration value."""
        keys = key.split('.')
        value = self.config
        
        for k in keys:
            if isinstance(value, dict):
                value = value.get(k)
                if value is None:
                    return default
            else:
                return default
                
        return value if value is not None else default
        
    def set(self, key, value):
        """Set a configuration value."""
        keys = key.split('.')
        config = self.config
        
        for k in keys[:-1]:
            if k not in config:
                config[k] = {}
            config = config[k]
            
        config[keys[-1]] = value
        
    def save(self):
        """Save configuration to file."""
        with open(self.config_file, 'w') as f:
            json.dump(self.config, f, indent=4)
