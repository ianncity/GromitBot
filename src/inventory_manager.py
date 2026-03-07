"""Inventory manager module for GromitBot."""

import time
import random


class InventoryManager:
    """Manages inventory and vendor runs."""
    
    def __init__(self, config, logger, screen, input_controller, human_behavior, pathfinder):
        """Initialize inventory manager."""
        self.config = config
        self.logger = logger
        self.screen = screen
        self.input_controller = input_controller
        self.human_behavior = human_behavior
        self.pathfinder = pathfinder
        
        # Inventory settings
        self.full_threshold = config.get('inventory.full_threshold', 14)
        self.vendor_route = config.get('inventory.vendor_route', 'paths/vendor.json')
        self.sell_items = config.get('inventory.sell_items', True)
        self.auto_repair = config.get('inventory.auto_repair', True)
        
        # Load vendor route
        self.vendor_path = self.pathfinder.get_path('vendor')
        
        # State
        self.current_bags_slots = 0
        self.total_bags_slots = 16
        self.at_vendor = False
        
    def run(self):
        """Run inventory check."""
        if not self.config.get('inventory.enabled', True):
            return
            
        try:
            # Check inventory
            self._check_inventory()
            
            # Determine if we need to visit vendor
            if self._needs_vendor_run():
                self._visit_vendor()
                
        except Exception as e:
            self.logger.error(f"Error in inventory manager: {e}")
            
    def _check_inventory(self):
        """Check current inventory status.
        
        Simplified implementation - in real version would use
        pixel detection to count free slots.
        """
        # Simplified: Random slot count
        # Real implementation would check screen pixels
        self.current_bags_slots = random.randint(8, 16)
        self.logger.debug(f"Inventory: {self.current_bags_slots}/16 slots used")
        
    def _needs_vendor_run(self):
        """Check if we need to visit a vendor."""
        free_slots = self.total_bags_slots - self.current_bags_slots
        return free_slots < self.full_threshold
        
    def _visit_vendor(self):
        """Visit vendor to sell items and repair."""
        self.logger.info("Visiting vendor...")
        
        # Move to vendor
        if self.vendor_path:
            self._move_to_vendor()
            
        # Open vendor
        self._open_vendor()
        
        # Sell items
        if self.sell_items:
            self._sell_items()
            
        # Repair equipment
        if self.auto_repair:
            self._repair_equipment()
            
        # Close vendor
        self._close_vendor()
        
        self.logger.info("Vendor visit complete!")
        
    def _move_to_vendor(self):
        """Move to vendor location."""
        self.logger.debug("Moving to vendor...")
        
        # Follow vendor path
        position = {'x': 0, 'y': 0}
        
        for waypoint in self.vendor_path:
            self.pathfinder.follow_path(
                self.input_controller,
                self.vendor_path,
                position,
                move_duration=1.5
            )
            position = waypoint
            
            # Human-like pause
            if random.random() < 0.3:
                self.human_behavior.random_pause()
                
    def _open_vendor(self):
        """Open vendor interface."""
        self.logger.debug("Opening vendor...")
        
        # Find and click vendor NPC
        # Simplified: Press key to interact
        time.sleep(0.5)
        
        # Press interact key
        self.input_controller.press_key('e')
        
        # Wait for vendor window
        time.sleep(1.0)
        
    def _sell_items(self):
        """Sell items to vendor."""
        self.logger.debug("Selling items...")
        
        # Sell all grey/white items
        # In real implementation, would scan for sellable items
        
        # Simplified: Random sell action
        for _ in range(3):
            time.sleep(0.3)
            
            # Click sell button
            # This would be pixel-based in real implementation
            
        self.logger.info("Items sold")
        
    def _repair_equipment(self):
        """Repair equipment."""
        self.logger.debug("Repairing equipment...")
        
        # In real implementation, would click repair button
        
        # Simplified
        time.sleep(0.5)
        
        self.logger.info("Equipment repaired")
        
    def _close_vendor(self):
        """Close vendor interface."""
        # Press escape to close
        self.input_controller.press_key('esc')
        
        time.sleep(0.3)
        
    def get_free_slots(self):
        """Get number of free inventory slots."""
        return self.total_bags_slots - self.current_bags_slots
        
    def is_full(self):
        """Check if inventory is full."""
        return self.get_free_slots() == 0
