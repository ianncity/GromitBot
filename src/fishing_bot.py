"""Fishing bot module for GromitBot."""

import time
import random


class FishingBot:
    """Bot for automated fishing."""
    
    def __init__(self, config, logger, screen, input_controller, human_behavior, state_manager):
        """Initialize fishing bot."""
        self.config = config
        self.logger = logger
        self.screen = screen
        self.input_controller = input_controller
        self.human_behavior = human_behavior
        self.state_manager = state_manager
        
        # Fishing settings
        self.cast_key = config.get('fishing.cast_key', '1')
        self.fishing_spot_colors = config.get('fishing.fishing_spot_colors', [[45, 100, 150], [50, 110, 160]])
        self.loot_range = config.get('fishing.loot_range', {
            'min_x': 500, 'max_x': 900,
            'min_y': 300, 'max_y': 600
        })
        self.wait_time_min = config.get('fishing.wait_time_min', 8000) / 1000
        self.wait_time_max = config.get('fishing.wait_time_max', 15000) / 1000
        
        # State
        self.is_fishing = False
        self.fish_caught = 0
        self.last_cast_time = 0
        
    def run(self):
        """Run one iteration of fishing bot."""
        if not self.config.get('fishing.enabled', True):
            return
            
        try:
            # Check if we need to loot
            if self._check_for_loot():
                self._loot()
                
            # Cast fishing line if not fishing
            if not self.is_fishing:
                self._cast()
                
            # Wait for fish
            self._wait_for_bite()
            
        except Exception as e:
            self.logger.error(f"Error in fishing loop: {e}")
            self.is_fishing = False
            
    def _cast(self):
        """Cast the fishing line."""
        self.logger.debug("Casting fishing line...")
        
        # Human-like delay
        self.human_behavior.apply_randomization()
        
        # Press cast key
        self.input_controller.press_key(self.cast_key)
        
        # Wait for cast animation
        time.sleep(1.5)
        
        self.is_fishing = True
        self.last_cast_time = time.time()
        self.logger.info("Fishing line cast")
        
    def _wait_for_bite(self):
        """Wait for a fish to bite."""
        wait_time = random.uniform(self.wait_time_min, self.wait_time_max)
        
        self.logger.debug(f"Waiting {wait_time:.1f}s for fish...")
        
        # Wait with occasional checks
        start_time = time.time()
        while time.time() - start_time < wait_time:
            # Check for bobber movement or bite indicator
            if self._detect_bite():
                self._reel_in()
                return
                
            # Random human-like pause
            if random.random() < 0.1:
                self.human_behavior.random_pause()
                
            time.sleep(0.5)
            
        # No bite, recast
        self.logger.debug("No bite, recasting...")
        self.is_fishing = False
        
    def _detect_bite(self):
        """Detect if a fish is biting (simplified implementation).
        
        In a full implementation, this would analyze screen pixels
        for fishing bobber movement or bite indicators.
        """
        # Simplified: Random detection for now
        # Real implementation would check for green sparkle or bobber movement
        return random.random() < 0.05
        
    def _reel_in(self):
        """Reel in the fish."""
        self.logger.debug("Fish detected! Reeling in...")
        
        # Press attack key to reel
        self.input_controller.press_key('1')
        
        # Wait for reel animation
        time.sleep(1.0)
        
        # Increment catch count
        self.fish_caught += 1
        self.state_manager.increment_stat('fishing_count')
        self.logger.info(f"Fish caught! Total: {self.fish_caught}")
        
        self.is_fishing = False
        
    def _check_for_loot(self):
        """Check if there's loot to pick up.
        
        Returns True if loot is available.
        """
        # Check for lootable items in loot range
        # Simplified: Random check for now
        return random.random() < 0.02
        
    def _loot(self):
        """Loot items."""
        self.logger.debug("Looting items...")
        
        # Move mouse to loot range and click
        loot_x = random.randint(
            self.loot_range['min_x'],
            self.loot_range['max_x']
        )
        loot_y = random.randint(
            self.loot_range['min_y'],
            self.loot_range['max_y']
        )
        
        # Human-like click
        self.human_behavior.click_humanlike(
            self.input_controller,
            loot_x,
            loot_y
        )
        
        time.sleep(0.5)
        
    def get_fish_count(self):
        """Get number of fish caught."""
        return self.fish_caught
