"""Input controller module for GromitBot."""

import time
import pyautogui
import keyboard
from pynput import keyboard as pynput_keyboard


class InputController:
    """Controller for keyboard and mouse input."""
    
    def __init__(self, config, logger):
        """Initialize input controller."""
        self.config = config
        self.logger = logger
        self.emergency_stop_key = config.get('general.emergency_stop_key', 'F9')
        self.emergency_stop_pressed = False
        
        # Setup pyautogui
        pyautogui.FAILSAFE = True
        pyautogui.PAUSE = 0
        
        # Setup emergency stop listener
        self._setup_emergency_stop()
        
    def _setup_emergency_stop(self):
        """Setup emergency stop key listener."""
        def on_press(key):
            try:
                if hasattr(key, 'char') and key.char == self.emergency_stop_key.lower():
                    self.emergency_stop_pressed = True
                elif key.name == self.emergency_stop_key.lower():
                    self.emergency_stop_pressed = True
            except:
                pass
                
        self.keyboard_listener = pynput_keyboard.Listener(on_press=on_press)
        self.keyboard_listener.daemon = True
        self.keyboard_listener.start()
        
    def is_emergency_stop_pressed(self):
        """Check if emergency stop was pressed."""
        return self.emergency_stop_pressed
        
    def reset_emergency_stop(self):
        """Reset emergency stop flag."""
        self.emergency_stop_pressed = False
        
    def key_down(self, key):
        """Press a key down."""
        try:
            keyboard.press(key)
        except Exception as e:
            self.logger.error(f"Error pressing key {key}: {e}")
            
    def key_up(self, key):
        """Release a key."""
        try:
            keyboard.release(key)
        except Exception as e:
            self.logger.error(f"Error releasing key {key}: {e}")
            
    def press_key(self, key, duration=0.05):
        """Press and release a key."""
        try:
            keyboard.press(key)
            time.sleep(duration)
            keyboard.release(key)
        except Exception as e:
            self.logger.error(f"Error pressing key {key}: {e}")
            
    def hold_key(self, key, duration):
        """Hold a key for a duration."""
        try:
            keyboard.press(key)
            time.sleep(duration)
            keyboard.release(key)
        except Exception as e:
            self.logger.error(f"Error holding key {key}: {e}")
            
    def mouse_move(self, x, y, duration=0.5):
        """Move mouse to position with human-like movement.
        
        Args:
            x, y: Target coordinates
            duration: Movement duration
        """
        try:
            pyautogui.moveTo(x, y, duration=duration)
        except Exception as e:
            self.logger.error(f"Error moving mouse: {e}")
            
    def mouse_click(self, x=None, y=None, button='left', clicks=1):
        """Click at position or current position.
        
        Args:
            x, y: Target coordinates (None for current)
            button: 'left', 'right', or 'middle'
            clicks: Number of clicks
        """
        try:
            if x is not None and y is not None:
                pyautogui.click(x, y, clicks=clicks, button=button)
            else:
                pyautogui.click(clicks=clicks, button=button)
        except Exception as e:
            self.logger.error(f"Error clicking: {e}")
            
    def mouse_down(self, button='left'):
        """Press mouse button down."""
        try:
            pyautogui.mouseDown(button=button)
        except Exception as e:
            self.logger.error(f"Error: {e}")
            
    def mouse_up(self, button='left'):
        """Release mouse button."""
        try:
            pyautogui.mouseUp(button=button)
        except Exception as e:
            self.logger.error(f"Error: {e}")
            
    def mouse_drag(self, x1, y1, x2, y2, duration=0.5):
        """Drag mouse from (x1, y1) to (x2, y2).
        
        Args:
            x1, y1: Start coordinates
            x2, y2: End coordinates
            duration: Drag duration
        """
        try:
            pyautogui.moveTo(x1, y1)
            pyautogui.dragTo(x2, y2, duration=duration, button='left')
        except Exception as e:
            self.logger.error(f"Error dragging: {e}")
            
    def scroll(self, clicks):
        """Scroll the mouse wheel.
        
        Args:
            clicks: Number of scrolls (positive for up, negative for down)
        """
        try:
            pyautogui.scroll(clicks)
        except Exception as e:
            self.logger.error(f"Error scrolling: {e}")
            
    def get_screen_size(self):
        """Get the screen size."""
        return pyautogui.size()
        
    def get_current_mouse_position(self):
        """Get current mouse position."""
        return pyautogui.position()
        
    def cleanup(self):
        """Cleanup input resources."""
        try:
            if hasattr(self, 'keyboard_listener'):
                self.keyboard_listener.stop()
        except:
            pass
