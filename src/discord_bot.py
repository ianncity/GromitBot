"""Discord bot module for GromitBot."""

import asyncio
import discord
from discord.ext import commands


class DiscordBot:
    """Discord bot for receiving commands."""
    
    def __init__(self, config, logger, bot_instance):
        """Initialize Discord bot."""
        self.config = config
        self.logger = logger
        self.bot_instance = bot_instance
        
        # Discord settings
        self.token = config.get('discord.token', '')
        self.command_channel = config.get('discord.command_channel', 'bot-commands')
        self.allowed_users = config.get('discord.allowed_users', [])
        
        # Setup Discord intents
        intents = discord.Intents.default()
        intents.message_content = True
        
        # Create bot
        self.bot = commands.Bot(command_prefix='!', intents=intents)
        self._setup_commands()
        
    def _setup_commands(self):
        """Setup bot commands."""
        
        @self.bot.event
        async def on_ready():
            self.logger.info(f"Discord bot logged in as {self.bot.user}")
            
        @self.bot.event
        async def on_message(message):
            # Ignore bot messages
            if message.author == self.bot.user:
                return
                
            # Check if in correct channel
            if message.channel.name != self.command_channel:
                return
                
            # Check allowed users
            if self.allowed_users and str(message.author.id) not in self.allowed_users:
                return
                
            await self.bot.process_commands(message)
            
        @self.bot.command(name='start')
        async def start_cmd(ctx):
            """Start the bot."""
            self.logger.info(f"Discord: start command received")
            self.bot_instance.running = True
            await ctx.send("✅ GromitBot started!")
            
        @self.bot.command(name='stop')
        async def stop_cmd(ctx):
            """Stop the bot."""
            self.logger.info(f"Discord: stop command received")
            self.bot_instance.stop()
            await ctx.send("🛑 GromitBot stopped!")
            
        @self.bot.command(name='pause')
        async def pause_cmd(ctx):
            """Pause the bot."""
            self.logger.info(f"Discord: pause command received")
            self.bot_instance.pause()
            await ctx.send("⏸️ GromitBot paused!")
            
        @self.bot.command(name='resume')
        async def resume_cmd(ctx):
            """Resume the bot."""
            self.logger.info(f"Discord: resume command received")
            self.bot_instance.resume()
            await ctx.send("▶️ GromitBot resumed!")
            
        @self.bot.command(name='status')
        async def status_cmd(ctx):
            """Get bot status."""
            status = self.bot_instance.get_status()
            
            status_msg = f"""📊 GromitBot Status:
- Running: {status['running']}
- Paused: {status['paused']}
- Current Task: {status['current_task']}
- Fishing: {status['state'].get('fishing_count', 0)}
- Herbalism: {status['state'].get('herbalism_count', 0)}
- Level: {status['state'].get('level', 1)}"""
            
            await ctx.send(status_msg)
            
        @self.bot.command(name='fish')
        async def fish_cmd(ctx):
            """Switch to fishing mode."""
            self.logger.info(f"Discord: fish command received")
            self.bot_instance.set_task('fishing')
            await ctx.send("🎣 Switched to fishing mode!")
            
        @self.bot.command(name='herb')
        async def herb_cmd(ctx):
            """Switch to herbalism mode."""
            self.logger.info(f"Discord: herb command received")
            self.bot_instance.set_task('herbalism')
            await ctx.send("🌿 Switched to herbalism mode!")
            
        @self.bot.command(name='level')
        async def level_cmd(ctx):
            """Switch to leveling mode."""
            self.logger.info(f"Discord: level command received")
            self.bot_instance.set_task('leveling')
            await ctx.send("⚔️ Switched to leveling mode!")
            
        @self.bot.command(name='help')
        async def help_cmd(ctx):
            """Show help message."""
            help_msg = """📖 GromitBot Commands:
!start - Start the bot
!stop - Stop the bot
!pause - Pause the bot
!resume - Resume the bot
!status - Get bot status
!fish - Switch to fishing
!herb - Switch to herbalism
!level - Switch to leveling"""
            
            await ctx.send(help_msg)
            
    def start(self):
        """Start the Discord bot."""
        if not self.token:
            self.logger.warning("Discord token not set, skipping Discord bot")
            return
            
        try:
            self.bot.run(self.token)
        except Exception as e:
            self.logger.error(f"Error starting Discord bot: {e}")
            
    def stop(self):
        """Stop the Discord bot."""
        try:
            asyncio.run(self.bot.close())
        except:
            pass
            
    async def send_message(self, message):
        """Send a message to Discord."""
        # This would be used for notifications
        pass
