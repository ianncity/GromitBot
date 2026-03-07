"""Human behavior module for GromitBot."""

import time
import random
import math


class HumanBehavior:
    """Module to simulate human-like behavior."""
    
    def __init__(self, config, logger):
        """Initialize human behavior module."""
        self.config = config
        self.logger = logger
        
        # Load human behavior settings
        self.min_delay = config.get('human_behavior.min_delay', 0.5)
        self.max_delay = config.get('human_behavior.max_delay', 2.0)
        self.mouse_speed_min = config.get('human_behavior.mouse_speed_min', 0.3)
        self.mouse_speed_max = config.get('human_behavior.mouse_speed_max', 1.2)
        self.pause_chance = config.get('human_behavior.pause_chance', 0.1)
        self.pause_duration_min = config.get('human_behavior.pause_duration_min', 2)
        self.pause_duration_max = config.get('human_behavior.pause_duration_max', 8)
        
    def random_delay(self):
        """Apply a random delay between actions."""
        delay = random.uniform(self.min_delay, self.max_delay)
        time.sleep(delay)
        
    def random_pause(self):
        """Randomly pause for a longer duration."""
        if random.random() < self.pause_chance:
            duration = random.uniform(
                self.pause_duration_min, 
                self.pause_duration_max
            )
            self.logger.debug(f"Human pause: {duration:.2f}s")
            time.sleep(duration)
            
    def get_random_mouse_speed(self):
        """Get a random mouse movement speed."""
        return random.uniform(self.mouse_speed_min, self.mouse_speed_max)
        
    def move_mouse_humanlike(self, input_controller, x, y):
        """Move mouse in a human-like manner with curves and variations.
        
        Args:
            input_controller: InputController instance
            x, y: Target coordinates
        """
        current_x, current_y = input_controller.get_current_mouse_position()
        
        # Calculate distance
        dx = x - current_x
        dy = y - current_y
        distance = math.sqrt(dx**2 + dy**2)
        
        if distance < 5:
            # Too close, just move directly
            input_controller.mouse_move(x, y, duration=0.1)
            return
            
        # Generate intermediate points for curved movement
        num_points = max(3, int(distance / 100))
        
        # Add randomness to path
        points = []
        for i in range(num_points + 1):
            t = i / num_points
            
            # Linear interpolation
            base_x = current_x + dx * t
            base_y = current_y + dy * t
            
            # Add curve offset
            offset = math.sin(t * math.pi) * random.uniform(-20, 20)
            
            # Add some randomness
            noise_x = random.uniform(-10, 10)
            noise_y = random.uniform(-10, 10)
            
            points.append((
                int(base_x + offset + noise_x),
                int(base_y + noise_y)
            ))
            
        # Move through points
        for i, (px, py) in enumerate(points):
            speed = self.get_random_mouse_speed()
            duration = distance / (500 * speed) / len(points)
            duration = max(0.05, min(duration, 0.3))
            
            input_controller.mouse_move(px, py, duration=duration)
            
        # Add slight overshoot and correction
        if random.random() < 0.3:
            overshoot_x = x + random.randint(-10, 10)
            overshoot_y = y + random.randint(-10, 10)
            input_controller.mouse_move(overshoot_x, overshoot_y, duration=0.1)
            input_controller.mouse_move(x, y, duration=0.1)
            
    def click_humanlike(self, input_controller, x=None, y=None, button='left'):
        """Perform a human-like click with movement and timing variations.
        
        Args:
            input_controller: InputController instance
            x, y: Target coordinates (None for current)
            button: Mouse button
        """
        # Move to target if specified
        if x is not None and y is not None:
            self.move_mouse_humanlike(input_controller, x, y)
            
            # Brief pause before clicking (like a human would)
            time.sleep(random.uniform(0.1, 0.3))
            
        # Randomize click position slightly
        if x is not None and y is not None:
            offset_x = random.randint(-3, 3)
            offset_y = random.randint(-3, 3)
            x += offset_x
            y += offset_y
            
        # Click with variable speed
        input_controller.mouse_down(button)
        time.sleep(random.uniform(0.05, 0.15))
        input_controller.mouse_up(button)
        
        # Random pause after click
        if random.random() < 0.3:
            time.sleep(random.uniform(0.1, 0.4))
            
    def rotate_character(self, input_controller, direction, duration=0.5):
        """Rotate character with mouse movement.
        
        Args:
            input_controller: InputController instance
            direction: 'left' or 'right'
            duration: Rotation duration
        """
        screen_width = input_controller.get_screen_size()[0]
        
        if direction == 'left':
            # Move mouse to left edge
            start_x = screen_width // 2
            end_x = 100
        else:
            # Move mouse to right edge
            start_x = screen_width // 2
            end_x = screen_width - 100
            
        # Get current mouse position
        current_y = input_controller.get_current_mouse_position()[1]
        
        # Move mouse to rotate
        input_controller.mouse_move(end_x, current_y, duration=duration)
        
    def random_look_around(self, input_controller):
        """Perform random look-around movement."""
        screen_width, screen_height = input_controller.get_screen_size()
        
        # Random position
        x = random.randint(100, screen_width - 100)
        y = random.randint(100, screen_height - 100)
        
        self.move_mouse_humanlike(input_controller, x, y)
        time.sleep(random.uniform(0.5, 1.5))
        
    def simulate_thinking(self):
        """Simulate thinking/hesitation delay."""
        if random.random() < 0.2:
            delay = random.uniform(0.5, 2.0)
            self.logger.debug(f"Simulating thinking: {delay:.2f}s")
            time.sleep(delay)
            
    def apply_randomization(self):
        """Apply general randomization to actions."""
        self.random_delay()
        self.random_pause()
        self.simulate_thinking()
