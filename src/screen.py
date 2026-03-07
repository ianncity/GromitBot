"""Screen capture module for GromitBot."""

import time
import numpy as np
import cv2
from PIL import ImageGrab, Image


class ScreenCapture:
    """Screen capture using multiple backends."""
    
    def __init__(self, config, logger):
        """Initialize screen capture."""
        self.config = config
        self.logger = logger
        self.game_window_title = config.get('screen.game_window_title', 'World of Warcraft')
        self.capture_region = config.get('screen.capture_region', {
            'x': 0, 'y': 0, 'width': 1920, 'height': 1080
        })
        
    def capture(self, region=None):
        """Capture screen region.
        
        Args:
            region: dict with x, y, width, height or None for full screen
            
        Returns:
            numpy array of the captured image
        """
        if region is None:
            region = self.capture_region
            
        try:
            # Use PIL ImageGrab for screen capture
            screenshot = ImageGrab.grab(bbox=(
                region['x'],
                region['y'],
                region['x'] + region['width'],
                region['y'] + region['height']
            ))
            
            # Convert to numpy array for OpenCV processing
            img_array = np.array(screenshot)
            
            # Convert RGB to BGR for OpenCV
            img_bgr = cv2.cvtColor(img_array, cv2.COLOR_RGB2BGR)
            
            return img_bgr
            
        except Exception as e:
            self.logger.error(f"Error capturing screen: {e}")
            return None
            
    def capture_color_at(self, x, y):
        """Get the color at a specific screen position.
        
        Args:
            x, y: Screen coordinates
            
        Returns:
            RGB tuple (r, g, b) or None
        """
        try:
            screenshot = ImageGrab.grab(bbox=(x, y, x+1, y+1))
            color = screenshot.getpixel((0, 0))
            return color  # Returns (r, g, b)
        except Exception as e:
            self.logger.error(f"Error getting color at ({x}, {y}): {e}")
            return None
            
    def find_color(self, color_range, region=None):
        """Find pixels matching a color range.
        
        Args:
            color_range: dict with 'min' and 'max' RGB arrays
            region: Screen region to search
            
        Returns:
            List of (x, y) coordinates matching the color
        """
        img = self.capture(region)
        if img is None:
            return []
            
        # Convert to HSV for better color matching
        hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
        
        # Define color range
        min_color = np.array(color_range['min'])
        max_color = np.array(color_range['max'])
        
        # Find matching pixels
        mask = cv2.inRange(hsv, min_color, max_color)
        
        # Find contours
        contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        
        # Get center points of contours
        points = []
        for contour in contours:
            if cv2.contourArea(contour) > 10:  # Filter small contours
                M = cv2.moments(contour)
                if M['m00'] > 0:
                    cx = int(M['m10'] / M['m00'])
                    cy = int(M['m01'] / M['m00'])
                    points.append((cx + region['x'], cy + region['y']) if region else (cx, cy))
                    
        return points
        
    def find_pixel_by_color(self, target_color, tolerance=10, region=None):
        """Find a pixel close to target color.
        
        Args:
            target_color: RGB tuple (r, g, b)
            tolerance: Color tolerance
            region: Screen region to search
            
        Returns:
            First (x, y) coordinate found or None
        """
        img = self.capture(region)
        if img is None:
            return None
            
        # Create color tolerance range
        min_color = np.array([max(0, c - tolerance) for c in target_color])
        max_color = np.array([min(255, c + tolerance) for c in target_color])
        
        # Convert to HSV
        hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
        
        # Create mask
        mask = cv2.inRange(hsv, min_color, max_color)
        
        # Find first white pixel
        coords = np.where(mask > 0)
        if len(coords[0]) > 0:
            y = coords[0][0]
            x = coords[1][0]
            return (x + region['x'], y + region['y']) if region else (x, y)
            
        return None
        
    def is_color_present(self, target_color, tolerance=20, region=None):
        """Check if a color is present in the region.
        
        Args:
            target_color: RGB tuple (r, g, b)
            tolerance: Color tolerance
            region: Screen region to search
            
        Returns:
            True if color is found, False otherwise
        """
        return self.find_pixel_by_color(target_color, tolerance, region) is not None
        
    def get_pixel_differences(self, region=None):
        """Get areas of the screen that have changed.
        
        Args:
            region: Screen region to check
            
        Returns:
            Number of changed pixels
        """
        # This is a simplified implementation
        # In a full implementation, you'd compare frames
        return 0
