#!/usr/bin/env python3
"""
GromitBot - World of Warcraft Pixelbot for Turtle WoW
A pixel-based bot with fishing, herbalism, and leveling capabilities.
"""

import sys
import os
import json
import time
import logging
import threading
import signal
from pathlib import Path

# Add src to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'src'))

from src.config import Config
from src.logger import setup_logger
from src.screen import ScreenCapture
from src.input import InputController
from src.human_behavior import HumanBehavior
from src.state import StateManager
from src.discord_bot import DiscordBot
from src.fishing_bot import FishingBot
from src.herbalism_bot import HerbalismBot
from src.leveling_bot import LevelingBot
from src.inventory_manager import InventoryManager
from src.pathfinding import PathFinder


class GromitBot:
    """Main bot class that coordinates all modules."""
    
    def __init__(self):
        self.logger = None
        self.config = None
        self.screen = None
        self.input_controller = None
        self.human_behavior = None
        self.state_manager = None
        self.discord_bot = None
        self.fishing_bot = None
        self.herbalism_bot = None
        self.leveling_bot = None
        self.inventory_manager = None
        self.pathfinder = None
        
        self.running = False
        self.current_task = None
        self.paused = False
        
    def initialize(self):
        """Initialize all bot components."""
        # Setup logging
        self.logger = setup_logger()
        self.logger.info("="*50)
        self.logger.info("GromitBot - Initializing")
        self.logger.info("="*50)
        
        # Load config
        self.config = Config()
        self.logger.info(f"Configuration loaded")
        
        # Initialize state manager
        self.state_manager = StateManager(self.logger)
        self.state_manager.load_state()
        self.logger.info("State manager initialized")
        
        # Initialize screen capture
        self.screen = ScreenCapture(self.config, self.logger)
        self.logger.info("Screen capture initialized")
        
        # Initialize input controller
        self.input_controller = InputController(self.config, self.logger)
        self.logger.info("Input controller initialized")
        
        # Initialize human behavior
        self.human_behavior = HumanBehavior(self.config, self.logger)
        self.logger.info("Human behavior module initialized")
        
        # Initialize pathfinder
        self.pathfinder = PathFinder(self.config, self.logger)
        self.logger.info("Pathfinder initialized")
        
        # Initialize bots
        self.fishing_bot = FishingBot(self.config, self.logger, self.screen, 
                                       self.input_controller, self.human_behavior, 
                                       self.state_manager)
        self.logger.info("Fishing bot initialized")
        
        self.herbalism_bot = HerbalismBot(self.config, self.logger, self.screen,
                                           self.input_controller, self.human_behavior,
                                           self.pathfinder, self.state_manager)
        self.logger.info("Herbalism bot initialized")
        
        self.leveling_bot = LevelingBot(self.config, self.logger, self.screen,
                                         self.input_controller, self.human_behavior,
                                         self.pathfinder, self.state_manager)
        self.logger.info("Leveling bot initialized")
        
        self.inventory_manager = InventoryManager(self.config, self.logger, self.screen,
                                                   self.input_controller, self.human_behavior,
                                                   self.pathfinder)
        self.logger.info("Inventory manager initialized")
        
        # Initialize Discord bot
        if self.config.get('discord.enabled', False):
            self.discord_bot = DiscordBot(self.config, self.logger, self)
            self.logger.info("Discord bot initialized")
        
        # Setup signal handlers
        signal.signal(signal.SIGINT, self._signal_handler)
        signal.signal(signal.SIGTERM, self._signal_handler)
        
        self.logger.info("="*50)
        self.logger.info("GromitBot - Initialization Complete")
        self.logger.info("="*50)
        
    def _signal_handler(self, signum, frame):
        """Handle shutdown signals."""
        self.logger.info("Received shutdown signal, stopping...")
        self.stop()
        
    def start(self):
        """Start the bot."""
        self.logger.info("Starting GromitBot...")
        self.running = True
        
        # Start Discord bot if enabled
        if self.discord_bot:
            self.discord_bot.start()
        
        # Main bot loop
        while self.running:
            try:
                if self.paused:
                    time.sleep(1)
                    continue
                
                # Check for emergency stop
                if self.input_controller.is_emergency_stop_pressed():
                    self.logger.warning("Emergency stop triggered!")
                    self.stop()
                    break
                
                # Execute current task
                self._execute_current_task()
                
                # Save state periodically
                self.state_manager.save_state_if_needed()
                
                # Small sleep to prevent CPU overuse
                time.sleep(0.1)
                
            except Exception as e:
                self.logger.error(f"Error in main loop: {e}", exc_info=True)
                self.state_manager.save_state()
                time.sleep(5)
                
        self.logger.info("GromitBot stopped")
        
    def _execute_current_task(self):
        """Execute the current active task."""
        if self.current_task == 'fishing':
            self.fishing_bot.run()
        elif self.current_task == 'herbalism':
            self.herbalism_bot.run()
        elif self.current_task == 'leveling':
            self.leveling_bot.run()
        elif self.current_task == 'inventory':
            self.inventory_manager.run()
        else:
            # Default: run all enabled bots
            if self.config.get('fishing.enabled', False):
                self.fishing_bot.run()
            elif self.config.get('herbalism.enabled', False):
                self.herbalism_bot.run()
            elif self.config.get('leveling.enabled', False):
                self.leveling_bot.run()
                
    def stop(self):
        """Stop the bot gracefully."""
        self.logger.info("Stopping GromitBot...")
        self.running = False
        
        # Stop Discord bot
        if self.discord_bot:
            self.discord_bot.stop()
            
        # Save state
        self.state_manager.save_state()
        
        # Cleanup
        if self.input_controller:
            self.input_controller.cleanup()
            
        self.logger.info("GromitBot stopped gracefully")
        
    def set_task(self, task):
        """Set the current task."""
        self.logger.info(f"Setting task to: {task}")
        self.current_task = task
        
    def pause(self):
        """Pause the bot."""
        self.logger.info("Bot paused")
        self.paused = True
        
    def resume(self):
        """Resume the bot."""
        self.logger.info("Bot resumed")
        self.paused = False
        
    def get_status(self):
        """Get current bot status."""
        return {
            'running': self.running,
            'paused': self.paused,
            'current_task': self.current_task,
            'state': self.state_manager.get_state()
        }


def main():
    """Main entry point."""
    bot = GromitBot()
    bot.initialize()
    bot.start()


if __name__ == '__main__':
    main()
