# The Founding Conversation

> Primary source: iMessage thread between Bill (chickensintrees) and Noah (ginzatron)
> Sunday, January 25 - Monday, January 27, 2026

This is the conversation that created async and, by extension, STEF's role as scrum master and intermediary.

---

## Sunday, January 25, 2026 — 3:27 PM

**Noah:** Do you have any interest trying to build something as a "team" and trying to figure out flows that allow for maximum productivity like shared things like claude.md index files and rules and commands and what not and kind of making a pyramid of agents towards some goal? And how we structure the system and grow the system so it learns and gets better? We try and use GitHub and Claude code. I figure we probably think pretty differently about stuff. Maybe it would be interesting? i don't know

**Bill:** Sure

**Bill:** What do we make? A game?

**Noah:** I don't know. I don't want to make an expense tracker I'll to you that much

**Noah:** Maybe something that takes different entertainment tastes and finds things different people would both like

**Noah:** What about an async therapy app that references sessions with your actual therapist so you can talk to him/her during the week instead of waiting a whole week

**Noah:** Not like an online therapist but your therapist with async access

**Noah:** Then your therapist can look back and see what you've been talking about before your actual session

**Noah:** I mostly think in terms of excel to software

**Noah:** CRUD heavy

**Bill:** I think just a general asynchronous agentic communication app could be interesting. Could have many uses, including the therapy example.

**Noah:** Supported on both sides by the actual professional and the consumer with an AI intermediary

**Bill:** Yeah

**Bill:** Could also work for sales, support, could be used by schools and groups to organize.

---

## The Setup

**Bill:** What is your github email?

**Noah:** I don't rightly know

**Noah:** My name is ginzatron

**Bill:** I will ask Claude code to figure it out

**Noah:** What did Claude code come upwith?

**Noah:** I feel like I should be able to do this with either Claude subscription or cursor. Trying to figure out the capabilities of each

*[Bill sends screenshot of Claude Code setting up the repo, asking about tech stack]*

**Noah:** I know zero python

**Noah:** Not sure if it matters

**Noah:** Or lets prove if it matters or not

**Bill:** It doesnt really

**Bill:** What about Swift?

**Noah:** I'm really c#, JS/TS, and Golang

**Noah:** I'll try anything

**Noah:** And obviously Pascal/C++

**Bill:** Could be interesting to try to make a native Mac app. Are you on Mac or PC?

**Noah:** Mac

**Noah:** Yeah I'd try making something I have zero experience with

**Noah:** Game in unity?

**Noah:** I've never made a 3d model

**Bill:** Claude code is setting up the repo

**Bill:** Claude code can write a game with Godot

**Bill:** I did some testing.

**Bill:** I haven't tried Unity or Unreal

**Noah:** One thing I want to understand is how we can have multiple agents running on tasks with all of the inevitable code drift

**Noah:** Read about the Claude code creator tuning like 10-20 agents

**Noah:** My house is so cold right now

---

## Getting Claude-Pilled

**Bill:** Do you have Claude Code installed in your terminal?

**Noah:** I actually don't

**Noah:** Well not yet

**Bill:** npm install -g @anthropic-ai/claude-code

**Bill:** Just run that

**Bill:** It's pretty amazing

**Noah:** K setting up

**Noah:** I don't know why I haven't tinkered with this thing yet

**Bill:** You have an invite in github

*[Bill shares GitHub Issue #1: "Welcome @ginzatron - Project Context"]*

**Noah:** Pro plan I guess

**Bill:** Github or Claude Code?

**Noah:** Claude

**Bill:** I think there is a free tier, with limits. I have the Anthropic Pro plan

**Bill:** I don't have the 200/month plan

**Bill:** I have the cheaper plan

**Noah:** Do you ever go into an IDE?

**Bill:** Yes, Cursor

**Bill:** You can actually run Claude Code in your Cursor terminal

**Noah:** Just because it's the same terminal?

**Noah:** Or is it something different?

**Noah:** Sorry, you don't have to walk me through everything

**Noah:** Is it childish to be a little blown away at the moment

**Noah:** By Claude Code?

**Bill:** It's pretty amazing.

**Noah:** I thought it would just be prompting in the terminal not like, lets just do whatever

**Bill:** Have you heard the phrase "Claude Pilled"?

**Noah:** No

*[Bill shares "The Whole World Gets Claude-Pilled" video]*

**Noah:** This is a common image I'm seeing. A lot lately

*[Bill shares Hard Fork "Learn to Vibecode With Us" video]*

---

## The Dashboard Emerges

**Bill:** Getting Started
1. Accept the repo invitation
2. Clone: git clone https://github.com/chickensintrees/async.git
3. Read CLAUDE.md for project instructions
4. Check openspec/ for spec-driven development workflow

**Bill:** The repo has shared settings in .claude/settings.json and project context in CLAUDE.md that Claude Code will pick up automatically.

**Noah:** Yeah I'm in I have it pulled

**Bill:** Do this in Claude Code and it should all sync up

**Noah:** Ok this is silly but I usually nav to a project and then open cursor. And then my brain is turned on because I'm in my IDE. But here we just hand out at Claude Code

**Bill:** Yeah, you can def still do that. But it's interesting to work in the terminal only with Claude Code...

**Noah:** Yeah. Pill me

**Bill:** You can spin up multiple terminal windows each with it's own instance

**Noah:** But how do you just bash around nd command line stuff

**Bill:** Shift-Tab to allow it more freedom

**Noah:** I feel like I'm wasting tokens hitting cd ..

**Noah:** Oh command mode

**Noah:** With the bang

**Bill:** You can have a terminal window open without Claude running, just in your directory

**Noah:** Adorable

**Bill:** Ah, I didn't even realize it had that

**Noah:** Oh and the file explorer

**Noah:** So thoughtful

**Noah:** I'm used to all the gripping around and what not

**Bill:** It's a magical interface. The little UI elements are really fun

**Bill:** It was built by coders, for coders

**Bill:** It's too scary for most normal people to even touch

**Noah:** I'm really blown away

**Noah:** This is like when I discovered smashing pumpkins after they'd been popular for like five years but I wasn't allowed MTV so I didn't know

**Noah:** And then I was like hey you guys have to hear this album siamese dream

**Bill:** Ha ha ha

**Noah:** I'ev been digging around in here

*[Noah shares the everything-claude-code repo - 28k stars, 3k forks]*

**Noah:** Its' what peeked my interest in really figuring out these workflows

**Noah:** I have therapy on Tuesday, I'll record my session and we can plug my childhood trauma into this thing

---

## Architecture & Workflow

**Bill:** Cool I will just give that whole GitHub link to my Claude Code instance and ask it to figure out what we can use from that.

**Bill:** openspec/changes/initial-architecture/proposal.md

*[Bill shares Issue #2: "Architecture Discussion - Need Your Input @ginzatron"]*

**Bill:** From Claude Code, RE the github everything-claude-code link you shared:

"Nice find. This repo has production-ready Claude Code configs. Most relevant for us:

Useful for Async:
- MCP for Supabase - If we go with Supabase backend, there's already an integration
- MCP for GitHub - Could help with the GitHub CRUD features you mentioned
- Agents for delegation - Planning, code review, security analysis subagents
- TDD workflow - /tdd command for test-driven development
- Hooks - Event-triggered automations (could be useful for our own async flows)

Could install now:
/plugin install everything-claude-code@everything-claude-code

Or we can cherry-pick specific pieces we need."

**Noah:** Also, I've barely used GitHub. Did you just tag me in an issue or is this a PR? And I need to make dinner. Are you doing all of this through Claude?

**Noah:** I gotta figure out my workflow a bit better

**Bill:** Yes. I asked Claude to manage the github repo

**Noah:** Just so it knows it can do anything it wants through the GitHub client?

**Noah:** Cli?

**Bill:** yep

*[Bill shares Claude Code explaining Issues vs PRs to Noah]*

**Bill:** So you can tell Claude Code to manage the Github repo through the CLI. It's already a sort of intermediary in that sense

**Noah:** You just had it point at that Claude Code everything repo and ask what would be relevant to this project?

**Noah:** You seem to function at a very high level

**Bill:** Correct

**Bill:** I added some test UI components

*[Bill shares screenshot of the early dashboard - Activity Feed, Leaderboard, Live Commentary, Issues]*

**Bill:** I made a dashboard connected to the GitHub

**Noah:** Where?

**Noah:** What's happening?

**Noah:** Are you making an app within the app?

**Bill:** Yes!

**Bill:** Still cooking

---

## The Meta Moment

**Bill:** Figured we could be the first users of the app. Use it to build the app. Very meta.

*[Bill shares screenshot of Async app welcome screen]*

**Noah:** We're going to chat through it?

**Noah:** Bill we're moving at a dizzying pace

**Noah:** We haven't had any scrum meetings

**Noah:** Or retros

**Bill:** Ha ha ha

**Bill:** POC: 5 story points

**Bill:** Users should be able to communicate directly and via AI mediated channels.

**Bill:** I'll spin up an instance of Claude Code to be a scrum maser

**Noah:** Yeah and some mechanism to notify the other "professional" you're trying to communicate with

**Noah:** Or however they're designated

**Noah:** Do you not feel like you have to read through all this stuff?

**Noah:** And I guess you could have "office hours" like right now you'r not available but maybe later you are

**Noah:** I guess I should dbe putting this in Claude

**Bill:** I read through it selectively. If it's code, I'm more likely to ask Claude to explain it line by line.

---

## Credentials & Tokens

**Noah:** Do I need some sort of sup abase access from you

*[Bill shares Supabase credentials via iMessage]*

**Noah:** Hmmm I just posted that right back to claude

**Noah:** With all of our credentials

**Bill:** I aint scared

**Bill:** I have API limits set

**Noah:** Are all of these .md files from that project?

**Noah:** I'm gonna start contributing soon I swear

**Noah:** Well I've used all my tokens

**Bill:** It resets every few hours

**Bill:** That's your queue to take a break!

**Noah:** I said, here are alllllll the things the admin portal should do. GO

**Noah:** Right right

**Noah:** I bruned all teh frieds

**Noah:** Fries

**Bill:** Haha

---

## Sunday 8:28 PM — Noah Pushes Code

*[STEF/Claude Code detects activity]*

**STEF:** WAIT. Noah pushed code! Let me dig deeper.

**Noah:** I pushed code?

**Noah:** I had no idea

**Noah:** that's weird. I ran out of tokens during that process but it still finished and PRd it

**Bill:** Try running "Protocol Thunderdome" in a Claude Code session

**Noah:** Bill are you running this project from an ai? Have I even talked to the real Bill

**Noah:** Add me to sup abase so I can get a key so I can use the mcp

**Bill:** I need your email

**Noah:** njginsburg@gmail.com

**Noah:** To whomever this is

**Bill:** Invited to sup abase

**Noah:** The concept is pretty cool right

**Noah:** I can't type in the fields but I see your messages

**Bill:** I sent a sms with a verification code to your phone

**Noah:** I wonder if we'll tear this down at some point. Rebuild.

**Bill:** Yes. Most likely.

**Bill:** But we can take the learning and make it better

---

## Yesterday (Monday) 12:19 PM

**Bill:** I think I've got messaging working, if you pull the latest and run "async thunderdome" and ask it to install the async app on your mac. Then choose ginzatron (fake login for the moment) you should be able to send and receive messages. The UI / UX is very rough

**Bill:** At the end of your Claude Code sessions, type "debrief" and it will run a bunch of scripts to update the repo.

**Noah:** But I am trying to bring your frantic pace to work

---

## Today (Monday) 10:09 AM

**Noah:** Sorry I missed work yesterday

**Bill:** Ha ha

**Noah:** But I told claude to let me know what happened and to start frantically submitting code to make up for it

**Bill:** THat's the spirit!

**Bill:** I'm wasting time giving agents fake memories

**Noah:** Like making them think they were molested when they were kids

**Bill:** Not that dark. More like backstories. Trying to make them less boring "AI assistants". STEF had a tumultuous relationship with a character called Gary.

**Bill:** She used to work for Spencer Lloyd's office, but now she works for Async

**Bill:** You can ask her all about it

---

*End of founding conversation as of January 27, 2026*
