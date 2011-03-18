require 'digest/sha2'
require 'fileutils'
require 'json'
require 'tmpdir'

# main function

# get directories for use later
@runDir= Dir.getwd
@repoDir = getRepositoryDirectory

# if we're not initializing and we have no repository
# issue an error and exit
if ARGV[0] != "init" && @repoDir.nil?
	repositoryIssueError
	Process.exit
end
# switch based on command
case ARGV[0]
when "init"
	if @repoDir.nil?
		init
	else
		puts "Repository already initialized"
	end
when "commit"
	commit ARGV[1]
when "replace"
	replace ARGV[1]
when "history"
	history
when "branch"
	if not ARGV[1].nil?
		branch ARGV[1]
	else
		listBranches
	end
when "checkout"
	checkout ARGV[1]
else
	help
end

# end main

# print an error that states that the program must be run in the directory
# with the repository, and that the repository needs to be initialized.
#
# this was a commonly used error, hence the function just for it.
def repositoryIssueError
	puts "The repository either has not been initialized 
		or this command is not being run from the base
		directory of the repository".gsub(/\s+/, " ").strip
end

# initialize a repository
def init
	Dir.mkdir(".tvc") unless Dir::exists?(".tvc")
	Dir.chdir(".tvc")
	Dir.mkdir("objects") unless Dir::exists?("objects")
	f = File.new("pointers", "w")
	f.puts JSON.generate [{"name" => "master", "hash" => nil, "parent" => nil}]
	f.close
	f = File.new("history", "w")
	f.puts JSON.generate []
	f.close
	f = File.new("current", "w")
	f.puts JSON.generate [{"name" => "master", "hash" => nil, "parent" => nil}]
	f.close
end

# commit current changes
def commit(message)
	Dir.chdir(getObjectsDirectory)
	hash = createObjects(@runDir)
	Dir.chdir(@repoDir)
	current = getCurrentEntry
	data = {"message" => message, "hash" => hash, "parent" => current["hash"]}
	addHistoryEntry(data)
	current["parent"] = data["parent"]
	current["hash"] = data["hash"]
	changeCurrentEntry(current)
	changeBranchHash(current["name"], current["hash"])
	puts hash
	puts message
end

# replace current files with requested version
def replace(versionHash)
	Dir.chdir(getObjectsDirectory)
	hash = getFullHash(versionHash)
	if not hash.nil? && File::exists?(hash)
		deleteFiles(@runDir)
		root = File.open(hash, "rb") { |f| f.read }
		rootInfo = JSON.parse root
		moveFiles(@runDir, rootInfo)
	else
		puts "This version does not exist"
		return
	end
end

# prints a list of commits up the chain
def history
	Dir.chdir(@repoDir)
	current = getCurrentEntry
	hash = current["hash"]
	history = File.open("history", "rb") { |f| f.read }
	versions = JSON.parse history
	while not hash.nil?
		versions.each do |version|
			if version["hash"] == hash
				puts "#{version["hash"]}\n#{version["message"]}\n\n"
				hash = version["parent"]
				break
			end
		end
	end
end

# create a branch
def branch(name)
	Dir.chdir(@repoDir)
	b = findBranch(name)
	if b.nil?
		current = getCurrentEntry
		newBranch = {"name" => name, "hash" => current["hash"], "parent" => current["hash"]}
		addBranchEntry(newBranch)
	else
		puts "Branch already exists"
	end
end

# checkout a branch
def checkout(branchName)
	Dir.chdir(@repoDir)
	checkoutBranch = findBranch(branchName)
	if not checkoutBranch.nil?
		changeCurrentEntry(checkoutBranch)
		replace(checkoutBranch["hash"])
	else
		puts "Branch does not exist"
		return
	end
end

# changes the hash for a specified branch, and sets the parent to the previous hash
def changeBranchHash(name, hash)
	b = findBranch(name)
	branches = getBranches
	branches.each do |branch|
		if branch == b
			branch["parent"] = branch["hash"]
			branch["hash"] = hash
			saveBranches(branches)
			return
		end
	end
end

# returns the path to the objects directory
def getObjectsDirectory
	return @repoDir + '/' + "objects"
end

# adds an entry to the history file
def addHistoryEntry(entry)
	versions = getHistoryEntries
	versions << entry
	historyFile = File.open("history", "w")
	historyFile.puts JSON.generate versions
	historyFile.close
end

# retrieves the history entries
def getHistoryEntries
	history = File.open("history", "rb") { |f| f.read }
	versions = JSON.parse history
end

# change the entry in the current file
def changeCurrentEntry(entry)
	newEntry = [entry]
	current = File.open("current", "w")
	current.truncate(0)
	current.puts JSON.generate newEntry
	current.close
end

# get the entry in the current file
def getCurrentEntry
	current = File.open("current", "rb") { |f| f.read }
	entry = (JSON.parse current)[0]
end

# get all branches
def getBranches
	pointers = File.open("pointers", "rb") { |f| f.read }
	branches = JSON.parse pointers
end

# find a branch.  nil if it does not exist
def findBranch(name)
	branches = getBranches
	branches.each do |branch|
		if branch["name"] == name
			return branch
		end
	end
	return nil
end

# gets a full hash if only given a short hash.
# allows for easier specification of revisions,
# but can be kind of dangerous if the short hash is too short
def getFullHash(hash)
	Dir.foreach(getObjectsDirectory) do |dir|
		dirpath = getObjectsDirectory + '/' + dir
		unless File.directory?(dirpath)
			if dir[0, hash.length] == hash
				return dir
			end
		end
	end
	return nil
end

# recursively deletes all files in the directory.
def deleteFiles(directoryName)
	Dir.foreach(directoryName) do |dir|
		dirpath = directoryName + '/' + dir
		if File.directory?(dirpath)
			if dir != '.' && dir != '..' && dir != ".tvc"
				deleteFiles(dirpath)
				Dir.delete(dirpath)
			end
		else
			File.delete(dirpath)
		end
	end
end

# gets files from the given json 
def moveFiles(directoryName, jsonInfo)
	jsonInfo.each do |item|
		# each "tree" item specifies a directory that should be made corresponding to 
		# that directory's json file (hash)
		if item["type"] == "tree"
			d = directoryName + '/' + item["name"]
			Dir.mkdir(d)
			dirFile = File.open(item["hash"], "rb") { |f| f.read }
			dirJson = JSON.parse dirFile
			moveFiles(d, dirJson)
		# copy the item out of the objects folder into its proper place
		elsif item["type"] == "blob"
			FileUtils.cp(File.join(getObjectsDirectory, item["hash"]), File.join(directoryName, item["name"]))
		end
	end
end

# prints a list of valid functions and their uses
def help
	puts "help - This text"
	puts "init - Initialize a repository"
	puts "commit - Commit changes to a repository"
	puts "branch - Create a new branch.  If not given a branch name, it lists all current branches."
	puts "checkout - Move to the specified branch for modifying"
	puts "replace - Pulls the desired revision down from the repository"
end

# save objects in the objects folder, based on hash
# create json files to index them
def createObjects(directoryName)
	objects = []
	Dir.foreach(directoryName) do |dir|
		dirpath = directoryName + '/' + dir
		# go down into each valid directory and make objects for its contents
		if File.directory?(dirpath)
			if dir != '.' && dir != '..' && dir != ".tvc"
				hash = createObjects(dirpath)
				data = { "type" => "tree", "name" => dir, "hash" => hash }
				objects << data
			end
		# create a hash based on the file contents
		else
			hash = createHash(dirpath)
			data = { "type" => "blob", "name" => dir, "hash" => hash }
			FileUtils.cp(dirpath, File.join(getObjectsDirectory, hash))
			objects << data
		end
	end
	# save off objects json file to a temp file
	tempFileName = File.join(getObjectsDirectory, "crap")
	tempFile = File.new(tempFileName, "w")
	tempFile.puts JSON.generate objects
	tempFile.close
	# get the hash for the temp file, save it as that, and return the hash
	hash = createHash(tempFileName)
	FileUtils.cp(tempFileName, File.join(getObjectsDirectory, hash))
	File.delete(tempFileName)
	return hash
end

# create a sha2 hash of a file
def createHash(filePath)
	hashfunc = Digest::SHA2.new
	open(filePath, "rb") do |io|
		while !io.eof
			readBuffer = io.readpartial(1024)
			hashfunc.update(readBuffer)
		end
	end
	return hashfunc.hexdigest
end

# add an entry to the branch list
def addBranchEntry(entry)
	branches = getBranches
	branches << entry
	saveBranches(branches)
end

# save off all branches
def saveBranches(branches)
	pointers = File.open("pointers", "w")
	pointers.truncate(0)
	pointers.puts JSON.generate branches
	pointers.close
end

# get the repository directory
def getRepositoryDirectory
	if Dir::exists?(".tvc")
		Dir.chdir(".tvc")
		return Dir.getwd
	end
	return nil
end

# list all existing branches
def listBranches
	branches = getBranches
	branches.each do |branch|
		puts branch["name"]
	end
end

