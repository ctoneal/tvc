TVC - Terrible Version Control
==============================

What TVC Is:
------------
TVC is a really terrible pseudo-remake of git in Ruby.  It should never really be used; its creation was a joke and a learning experience.  It will always be inferior to git.  I read a blog post called [The Git Parable](http://tom.preston-werner.com/2009/05/19/the-git-parable.html), and wrote it based on some of the explanations given there.  It's not a terribly well written piece of code, just a script I hacked together in the span of about a day.  I'm slowly adding to and revising it, but don't expect much.  If you're the version control police, please don't arrest me.  It was all meant as good fun, I swear!

Also, this is the first real thing I've written in Ruby.  It's not going to be pretty, and I'm pretty sure I'm not doing things "the Ruby way" or whatever.  Be gentle.

However, you might find it interesting to look at.  It works in limited situations: if you only want a local repository, and you don't need a whole lot of features or quality, well, it might do.  

Features (if you can call them that):
---------
* Storing versions
* Branching
* Merging (but it's a pretty terrible merge right now, don't trust it!)
* Viewing a list of commits for the branch you're on
* Pulling a previous revision

What You Need:
-------------
* Ruby (I made it using 1.9.2, but I don't think there's anything really specific to 1.9 in there)
* json gem (gem install json)
* diff-lcs gem (gem install diff-lcs)
* The desire to use sub-par code

What To Do:
-----------
Well, if you're still reading after all my warnings, I guess you want to try this out.  You're crazy.  

First, put tvc.rb somewhere you'll remember.  Don't put it in the directory you're wanting the repository in, otherwise it will be in your repository, and you don't really need that.  Go to where you want your repository and type:
	
	% ruby <path to tvc.rb> init
	
This will initialize the repository.  After that, commit like so:

	% ruby <path to tvc.rb> commit "some message about committing"
	
And of course, it's going to be the same anytime you want to commit changes to the repository.  To branch, type:

	% ruby <path to tvc.rb> branch <some name for the branch>
	
If no name is specified, it will list all current branches.  To move to a branch, type:

	% ruby <path to tvc.rb> checkout <name of a branch>
	
Now you're on that branch, ready to modify it.  Once you've committed changes to the branch and want to merge them in somewhere else (say, for instance, the master branch), type:

	% ruby <path to tvc.rb> checkout <branch you want to merge into>
	% ruby <path to tvc.rb> merge <branch you want to merge from>
	
By now, you've noticed each commit has a corresponding SHA-2 hash.  If you want to roll back to a revision, type:
	
	% ruby <path to tvc.rb> replace <the hash of the commit you want>
	
You don't have to type the whole hash, you can type just a few characters off the front of it.  You run the risk of messing up, I suppose.  Be careful.  To get a list of all commits up the tree from where you currently are, type:

	% ruby <path to tvc.rb> history
	
And, if you ever forget these few commands, they're accessible by typing:

	% ruby <path to tvc.rb> 
	
or

	% ruby <path to tvc.rb> help
	

Things That Might Happen Eventually:
-------------
* Viewable diffs and statuses.
* Make this into some sort of distributable form so I can stop typing "ruby <path to tvc.rb> blah blah blah" (but let's be honest, Ruby is kind of crap for this)
* Unit tests.  Probably should have started with those, but oh well.