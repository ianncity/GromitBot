"""Pathfinding module for GromitBot."""

import json
import math
import heapq
from pathlib import Path


class PathFinder:
    """A* pathfinding for navigation."""
    
    def __init__(self, config, logger):
        """Initialize pathfinder."""
        self.config = config
        self.logger = logger
        self.paths = {}
        self._load_paths()
        
    def _load_paths(self):
        """Load path files."""
        paths_dir = Path('paths')
        paths_dir.mkdir(exist_ok=True)
        
        # Load each path file
        for path_file in paths_dir.glob('*.json'):
            try:
                with open(path_file, 'r') as f:
                    path_data = json.load(f)
                    self.paths[path_file.stem] = path_data
                    self.logger.info(f"Loaded path: {path_file.stem}")
            except Exception as e:
                self.logger.error(f"Error loading path {path_file}: {e}")
                
    def get_path(self, path_name):
        """Get a path by name."""
        return self.paths.get(path_name, [])
        
    def add_path(self, path_name, waypoints):
        """Add a new path."""
        self.paths[path_name] = waypoints
        
    def save_path(self, path_name):
        """Save path to file."""
        paths_dir = Path('paths')
        path_file = paths_dir / f"{path_name}.json"
        
        try:
            with open(path_file, 'w') as f:
                json.dump(self.paths[path_name], f, indent=4)
            self.logger.info(f"Path saved: {path_name}")
        except Exception as e:
            self.logger.error(f"Error saving path: {e}")
            
    def find_nearest_waypoint(self, current_pos, path):
        """Find the nearest waypoint in a path."""
        if not path:
            return None
            
        min_dist = float('inf')
        nearest_idx = 0
        
        for i, waypoint in enumerate(path):
            dist = self._distance(current_pos, waypoint)
            if dist < min_dist:
                min_dist = dist
                nearest_idx = i
                
        return nearest_idx
        
    def _distance(self, pos1, pos2):
        """Calculate distance between two positions."""
        dx = pos1['x'] - pos2['x']
        dy = pos1['y'] - pos2['y']
        return math.sqrt(dx**2 + dy**2)
        
    def get_next_waypoint(self, path, current_idx):
        """Get the next waypoint in the path."""
        if not path:
            return None
            
        next_idx = (current_idx + 1) % len(path)
        return path[next_idx], next_idx
        
    def follow_path(self, input_controller, path, current_pos, move_duration=1.0):
        """Follow a path and move to next waypoint.
        
        Args:
            input_controller: InputController instance
            path: List of waypoints
            current_pos: Current position dict with x, y
            move_duration: How long to hold movement keys
            
        Returns:
            New position or None
        """
        if not path:
            return None
            
        # Find nearest waypoint
        current_idx = self.find_nearest_waypoint(current_pos, path)
        if current_idx is None:
            return None
            
        # Get next waypoint
        result = self.get_next_waypoint(path, current_idx)
        if result is None:
            return None
            
        next_waypoint, next_idx = result
        
        # Calculate direction
        dx = next_waypoint['x'] - current_pos['x']
        dy = next_waypoint['y'] - current_pos['y']
        
        # Normalize and determine movement keys
        dist = math.sqrt(dx**2 + dy**2)
        
        if dist < 5:
            # Reached waypoint, return new position
            return next_waypoint
            
        # Determine movement direction
        self._move_towards(input_controller, dx, dy, dist, move_duration)
        
        # Return estimated new position
        return {
            'x': current_pos['x'] + (dx / dist) * move_duration * 10,
            'y': current_pos['y'] + (dy / dist) * move_duration * 10
        }
        
    def _move_towards(self, input_controller, dx, dy, dist, duration):
        """Move towards a direction."""
        # Normalize
        dx_norm = dx / dist
        dy_norm = dy / dist
        
        # Determine key combinations
        keys_pressed = []
        
        # Horizontal movement
        if dx_norm > 0.3:
            keys_pressed.append('d')
        elif dx_norm < -0.3:
            keys_pressed.append('a')
            
        # Vertical movement
        if dy_norm > 0.3:
            keys_pressed.append('s')
        elif dy_norm < -0.3:
            keys_pressed.append('w')
            
        # Press keys
        for key in keys_pressed:
            input_controller.key_down(key)
            
        # Hold for duration
        import time
        time.sleep(duration)
        
        # Release keys
        for key in keys_pressed:
            input_controller.key_up(key)
            
    def create_circular_path(self, center_x, center_y, radius, num_points=8):
        """Create a circular path."""
        path = []
        
        for i in range(num_points):
            angle = (2 * math.pi * i) / num_points
            x = center_x + radius * math.cos(angle)
            y = center_y + radius * math.sin(angle)
            path.append({'x': int(x), 'y': int(y)})
            
        return path
        
    def create_rectangular_path(self, x, y, width, height):
        """Create a rectangular path."""
        return [
            {'x': x, 'y': y},
            {'x': x + width, 'y': y},
            {'x': x + width, 'y': y + height},
            {'x': x, 'y': y + height}
        ]
