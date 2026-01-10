The three files docker-compose.yml, .env and custom.ini are the basis for numerous WordPress sites I have created and maintained over the years. Typically, they run in a Proxmox LXC with docker installed. While they provide for multiple sites to be hosted on a single server, I prefer to give each site its own LXC.

One feature I have not addressed, though, is staging. I would like a straightforward and robust way to be able to stage changes before committing them to production, and the ability to revert.

Consider my options and let's make a plan to implement that