"""Leveling bot module for GromitBot."""

import time
import random


class LevelingBot:
    """Bot for automated leveling/questing."""
    
    def __init__(self, config, logger, screen, input_controller, human_behavior, pathfinder, state_manager):
        """Initialize leveling bot."""
        self.config = config
        self.logger = logger
        self.screen = screen
        self.input_controller = input_controller
        self.human_behavior = human_behavior
        self.pathfinder = pathfinder
        self.state_manager = state_manager
        
        # Leveling settings
        self.path_file = config.get('leveling.path_file', 'paths/leveling.json')
        self.combat_key = config.get('leveling.combat_key', '1')
        self.target_range = config.get('leveling.target_range', 30)
        self.pull_distance = config.get('leveling.pull_distance', 40)
        self.rest_threshold = config.get('leveling.rest_threshold', 0.3)
        self.food_key = config.get('leveling.food_key', '2')
        self.drink_key = config.get('leveling.drink_key', '3')
        
        # Load path
        self.path = self.pathfinder.get_path('leveling')
        
        # State
        self.level = 1
        self.xp = 0
        self.current_waypoint_index = 0
        self.current_position = {'x': 0, 'y': 0}
        self.health = 100
        self.mana = 100
        self.in_combat = False
        self.target_found = False
        
    def run(self):
        """Run one iteration of leveling bot."""
        if not self.config.get('leveling.enabled', False):
            return
            
        try:
            # Check resources
            self._check_resources()
            
            if self.health < self.rest_threshold * 100:
                self._rest()
                return
                
            # Look for targets
            if not self.in_combat:
                target = self._find_target()
                
                if target:
                    self._pull_target(target)
                else:
                    # Move along path
                    self._move_along_path()
            else:
                # Combat loop
                self._combat_loop()
                
        except Exception as e:
            self.logger.error(f"Error in leveling loop: {e}")
            
    def _find_target(self):
        """Find a target to attack.
        
        Returns:
            Target position or None
        """
        self.logger.debug("Looking for targets...")
        
        # Simplified: Check for enemy color (red)
        # In real implementation, would use pixel detection
        target_color_range = {
            'min': [150, 30, 30],
            'max': [200, 80, 80]
        }
        
        targets = self.screen.find_color(target_color_range)
        
        if targets:
            self.logger.info(f"Target found at {targets[0]}")
            return targets[0]
            
        return None
        
    def _pull_target(self, target_position):
        """Pull a target."""
        self.logger.debug(f"Pulling target at {target_position}")
        
        # Move towards target if too far
        dist = ((target_position[0] - self.current_position['x'])**2 +
                (target_position[1] - self.current_position['1'])**2)**0.5
        
        if dist > self.target_range:
            # Move closer
            self.pathfinder._move_towards(
                self.input_controller,
                target_position[0] - self.current_position['x'],
                target_position[1] - self.current_position['y'],
                dist,
                1.0
            )
            
        # Target the enemy
        self.human_behavior.click_humanlike(
            self.input_controller,
            target_position[0],
            target_position[1]
        )
        
        # Wait for target
        time.sleep(0.5)
        
        # Start attacking
        self.input_controller.press_key(self.combat_key)
        
        self.in_combat = True
        self.target_found = True
        self.logger.info("Engaged target!")
        
    def _combat_loop(self):
        """Handle combat."""
        # Check if target is dead
        if not self._is_target_alive():
            self.logger.info("Target defeated!")
            self._loot_and_skinn()
            self.in_combat = False
            self.target_found = False
            self.xp += random.randint(50, 100)
            self._check_level_up()
            return
            
        # Continue attacking
        self.input_controller.press_key(self.combat_key)
        
        # Random delay between attacks
        time.sleep(random.uniform(1.0, 2.0))
        
    def _is_target_alive(self):
        """Check if current target is still alive."""
        # Simplified: Random check
        # Real implementation would check for enemy health bar
        return random.random() < 0.8
        
    def _loot_and_skinn(self):
        """Loot and skin the defeated target."""
        self.logger.debug("Looting target...")
        
        # Random loot delay
        time.sleep(random.uniform(0.5, 1.5))
        
        # Press loot key
        self.input_controller.press_key('l')
        
        time.sleep(0.5)
        
    def _check_resources(self):
        """Check health and mana."""
        # Simplified: Random values
        # Real implementation would check status bars
        self.health = random.randint(50, 100)
        self.mana = random.randint(40, 100)
        
    def _rest(self):
        """Rest to recover health and mana."""
        self.logger.info("Resting to recover...")
        
        # Eat food
        self.input_controller.press_key(self.food_key)
        time.sleep(1.0)
        
        # Drink
        if self.mana < 50:
            self.input_controller.press_key(self.drink_key)
            time.sleep(1.0)
            
        # Wait for recovery
        time.sleep(3.0)
        
        self.health = 100
        self.mana = 100
        self.logger.info("Rest complete!")
        
    def _check_level_up(self):
        """Check for level up."""
        xp_needed = self.level * 1000
        
        if self.xp >= xp_needed:
            self.level += 1
            self.xp = 0
            self.logger.info(f"LEVEL UP! Now level {self.level}")
            
    def _move_along_path(self):
        """Move along the defined path."""
        if not self.path:
            self.logger.warning("No leveling path defined")
            return
            
        # Get current waypoint
        waypoint = self.path[self.current_waypoint_index]
        
        # Move towards waypoint
        new_pos = self.pathfinder.follow_path(
            self.input_controller,
            self.path,
            self.current_position,
            move_duration=1.5
        )
        
        if new_pos:
            self.current_position = new_pos
            
        # Check if reached waypoint
        dist = ((waypoint['x'] - self.current_position['x'])**2 +
                (waypoint['y'] - self.current_position['y'])**2)**0.5
        
        if dist < 10:
            self.current_waypoint_index = (self.current_waypoint_index + 1) % len(self.path)
            
        # Random look around
        if random.random() < 0.1:
            self.human_behavior.random_look_around(self.input_controller)
