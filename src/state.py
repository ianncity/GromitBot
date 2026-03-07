"""State management module for GromitBot."""

import json
import time
from pathlib import Path


class StateManager:
    """Manages bot state persistence and recovery."""
    
    def __init__(self, logger):
        """Initialize state manager."""
        self.logger = logger
        self.state_file = 'bot_state.json'
        self.state = {
            'current_task': None,
            'position': {'x': 0, 'y': 0, 'z': 0},
            'health': 100,
            'mana': 100,
            'inventory_count': 0,
            'level': 1,
            'xp': 0,
            'fishing_count': 0,
            'herbalism_count': 0,
            'last_save_time': 0,
            'task_state': {}
        }
        self.last_save_time = 0
        self.save_interval = 60  # seconds
        
    def load_state(self):
        """Load state from file."""
        state_path = Path(self.state_file)
        
        if state_path.exists():
            try:
                with open(state_path, 'r') as f:
                    loaded_state = json.load(f)
                    self.state.update(loaded_state)
                    self.logger.info("State loaded successfully")
            except Exception as e:
                self.logger.error(f"Error loading state: {e}")
        else:
            self.logger.info("No previous state found, starting fresh")
            
    def save_state(self):
        """Save state to file."""
        try:
            self.state['last_save_time'] = time.time()
            self.last_save_time = self.state['last_save_time']
            
            with open(self.state_file, 'w') as f:
                json.dump(self.state, f, indent=4)
                
            self.logger.debug(f"State saved at {time.strftime('%H:%M:%S')}")
            
        except Exception as e:
            self.logger.error(f"Error saving state: {e}")
            
    def save_state_if_needed(self):
        """Save state if enough time has passed."""
        current_time = time.time()
        
        if current_time - self.last_save_time >= self.save_interval:
            self.save_state()
            
    def get_state(self):
        """Get current state."""
        return self.state.copy()
        
    def update_state(self, key, value):
        """Update a specific state value."""
        self.state[key] = value
        
    def get_task_state(self, task_name):
        """Get state for a specific task."""
        return self.state.get('task_state', {}).get(task_name, {})
        
    def update_task_state(self, task_name, task_state):
        """Update state for a specific task."""
        if 'task_state' not in self.state:
            self.state['task_state'] = {}
            
        self.state['task_state'][task_name] = task_state
        
    def update_position(self, x, y, z=0):
        """Update character position."""
        self.state['position'] = {'x': x, 'y': y, 'z': z}
        
    def update_resources(self, health=None, mana=None):
        """Update health and mana values."""
        if health is not None:
            self.state['health'] = health
        if mana is not None:
            self.state['mana'] = mana
            
    def update_inventory(self, count):
        """Update inventory count."""
        self.state['inventory_count'] = count
        
    def increment_stat(self, stat_name, amount=1):
        """Increment a statistic."""
        if stat_name in self.state:
            self.state[stat_name] += amount
        else:
            self.state[stat_name] = amount
            
    def get_position(self):
        """Get current position."""
        return self.state.get('position', {'x': 0, 'y': 0, 'z': 0})
        
    def clear_state(self):
        """Clear all state data."""
        self.state = {
            'current_task': None,
            'position': {'x': 0, 'y': 0, 'z': 0},
            'health': 100,
            'mana': 100,
            'inventory_count': 0,
            'level': 1,
            'xp': 0,
            'fishing_count': 0,
            'herbalism_count': 0,
            'last_save_time': time.time(),
            'task_state': {}
        }
        self.save_state()
        self.logger.info("State cleared")
