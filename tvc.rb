require 'digest/sha2'
require 'fileutils'
require 'json'
require 'tmpdir'
require 'diff/lcs'

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
	@repoDir = getRepositoryDirectory
	Dir.mkdir(getObjectsDirectory) unless Dir::exists?(getObjectsDirectory)
	saveDataToJson(File.join(@repoDir, "pointers"), [{"name" => "master", "hash" => nil, "parent" => nil}])
	saveDataToJson(File.join(@repoDir, "history"), [])
	saveDataToJson(File.join(@repoDir, "current"), [{"name" => "master", "hash" => nil, "parent" => nil}])
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
		rootInfo = getDataFromJson(File.join(getObjectsDirectory, hash))
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
	versions = getHistoryEntries
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

# merges a branch into the current branch
# i'm betting this is going to look like crap
def merge(branchName)
	source = findBranch(branchName)
	target = getCurrentEntry
	if not source.nil?
	else
		puts "Branch doesn't exist"
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
	puts "merge - Merges the specified branch with the current branch"
end

# extracts json data from a given file
def getDataFromJson(filePath)
	fileText = File.open(filePath, "rb") { |f| f.read }
	fileJson = JSON.parse fileText
end

# puts data in json format in a given file
# warning:  this will replace all text in the file
def saveDataToJson(filePath, data)
	file = File.open(filePath, "w")
	file.truncate(0)
	file.puts JSON.generate data
	file.close
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
	saveDataToJson(File.join(@repoDir, "history"), versions)
end

# retrieves the history entries
def getHistoryEntries
	history = getDataFromJson(File.join(@repoDir, "history"))
end

# change the entry in the current file
def changeCurrentEntry(entry)
	newEntry = [entry]
	saveDataToJson(File.join(@repoDir, "current"), newEntry)
end

# get the entry in the current file
def getCurrentEntry
	current = (getDataFromJson(File.join(@repoDir, "current")))[0]
end

# get all branches
def getBranches
	branches = getDataFromJson(File.join(@repoDir, "pointers"))
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
			dirJson = getDataFromJson(File.join(getObjectsDirectory, item["hash"]))
			moveFiles(d, dirJson)
		# copy the item out of the objects folder into its proper place
		elsif item["type"] == "blob"
			FileUtils.cp(File.join(getObjectsDirectory, item["hash"]), File.join(directoryName, item["name"]))
		end
	end
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
	tempFileName = File.join(@repoDir, "temp")
	saveDataToJson(tempFileName, objects)
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
	saveDataToJson(File.join(@repoDir, "pointers"), branches)
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
when "merge"
	merge ARGV[1]
else
	help
end

# end main
