"""Herbalism bot module for GromitBot."""

import time
import random


class HerbalismBot:
    """Bot for automated herbalism gathering."""
    
    def __init__(self, config, logger, screen, input_controller, human_behavior, pathfinder, state_manager):
        """Initialize herbalism bot."""
        self.config = config
        self.logger = logger
        self.screen = screen
        self.input_controller = input_controller
        self.human_behavior = human_behavior
        self.pathfinder = pathfinder
        self.state_manager = state_manager
        
        # Herbalism settings
        self.path_file = config.get('herbalism.path_file', 'paths/herbalism.json')
        self.gather_key = config.get('herbalism.gather_key', '4')
        self.herb_color_range = config.get('herbalism.herb_color_range', {
            'min': [40, 120, 40],
            'max': [80, 180, 80]
        })
        self.scan_interval = config.get('herbalism.scan_interval', 500) / 1000
        
        # Load path
        self.path = self.pathfinder.get_path('herbalism')
        
        # State
        self.herbs_gathered = 0
        self.current_waypoint_index = 0
        self.current_position = {'x': 0, 'y': 0}
        
    def run(self):
        """Run one iteration of herbalism bot."""
        if not self.config.get('herbalism.enabled', True):
            return
            
        try:
            # Scan for herbs
            herb_position = self._scan_for_herbs()
            
            if herb_position:
                self._gather_herb(herb_position)
            else:
                # Move along path
                self._move_along_path()
                
        except Exception as e:
            self.logger.error(f"Error in herbalism loop: {e}")
            
    def _scan_for_herbs(self):
        """Scan screen for herb nodes.
        
        Returns:
            Position (x, y) of herb or None
        """
        self.logger.debug("Scanning for herbs...")
        
        # Find herbs by color
        herb_positions = self.screen.find_color(self.herb_color_range)
        
        if herb_positions:
            # Get nearest herb
            nearest = self._find_nearest_herb(herb_positions)
            self.logger.info(f"Found herb at {nearest}")
            return nearest
            
        return None
        
    def _find_nearest_herb(self, herb_positions):
        """Find the nearest herb to current position."""
        if not herb_positions:
            return None
            
        min_dist = float('inf')
        nearest = None
        
        for pos in herb_positions:
            dist = ((pos[0] - self.current_position['x'])**2 + 
                   (pos[1] - self.current_position['y'])**2)**0.5
            if dist < min_dist:
                min_dist = dist
                nearest = pos
                
        return nearest
        
    def _gather_herb(self, herb_position):
        """Gather a herb at the given position."""
        self.logger.debug(f"Gathering herb at {herb_position}")
        
        # Human-like approach
        self.human_behavior.apply_randomization()
        
        # Move to herb
        self.human_behavior.move_mouse_humanlike(
            self.input_controller,
            herb_position[0],
            herb_position[1]
        )
        
        # Click on herb
        self.human_behavior.click_humanlike(
            self.input_controller,
            herb_position[0],
            herb_position[1]
        )
        
        # Wait for gather animation
        time.sleep(2.0)
        
        # Press gather key if needed
        self.input_controller.press_key(self.gather_key)
        
        # Wait for gather to complete
        time.sleep(1.5)
        
        # Increment herb count
        self.herbs_gathered += 1
        self.state_manager.increment_stat('herbalism_count')
        self.logger.info(f"Herb gathered! Total: {self.herbs_gathered}")
        
    def _move_along_path(self):
        """Move along the defined path."""
        if not self.path:
            self.logger.warning("No herbalism path defined")
            # Simple random movement if no path
            self._random_wander()
            return
            
        # Get current waypoint
        waypoint = self.path[self.current_waypoint_index]
        
        self.logger.debug(f"Moving to waypoint {self.current_waypoint_index}: {waypoint}")
        
        # Move towards waypoint
        new_pos = self.pathfinder.follow_path(
            self.input_controller,
            self.path,
            self.current_position,
            move_duration=1.0
        )
        
        if new_pos:
            self.current_position = new_pos
            
        # Check if reached waypoint
        dist = ((waypoint['x'] - self.current_position['x'])**2 +
                (waypoint['y'] - self.current_position['y'])**2)**0.5
        
        if dist < 10:
            # Move to next waypoint
            self.current_waypoint_index = (self.current_waypoint_index + 1) % len(self.path)
            
    def _random_wander(self):
        """Random wandering when no path is defined."""
        # Random mouse movement
        screen_size = self.input_controller.get_screen_size()
        
        rand_x = random.randint(100, screen_size[0] - 100)
        rand_y = random.randint(100, screen_size[1] - 100)
        
        # Look around
        self.human_behavior.random_look_around(self.input_controller)
        
    def get_herbs_count(self):
        """Get number of herbs gathered."""
        return self.herbs_gathered
