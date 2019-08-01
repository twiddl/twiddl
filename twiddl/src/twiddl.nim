import os, json, strutils, times, options, sequtils

const
  ## The time format used throughout twiddl
  timeFmt = initTimeFormat("yyyy-MM-dd HH:mm:ss")

type
  TwiddlEnv* = object
    ## Holds all important data about a twiddl
    ## environment
    path*:string
    twiddlfile*:Twiddlfile
    builds*:seq[Build]
  Twiddlfile* = object
    ## Holds all configuration data for a twiddl
    ## environment
    path*:string
    name*:string
    jobs*:seq[Job]

  Job* = object
    ## Holds all data representing a specific job,
    ## something that can be run
    name*:string
    commands*:seq[string]
    artifacts*:seq[string]

  BuildStatus* = enum
    ## All possible states of a build
    bsUnknown,
    bsPlanned,
    bsPending,
    bsRunning,
    bsFinishedSuccessful,
    bsFinishedCanceled,
    bsFinishedFailed,

  Build* = object
    ## Holds all data tied to a build
    path*:string
    id*:int
    comment*:string
    job*:Job
    timeStarted*:Option[DateTime]
    timeFinished*:Option[DateTime]
    status*:BuildStatus
    logs*:seq[Log]
    artifacts*:seq[Artifact]

  Artifact* = object
    ## Holds all data tied to a build artifact
    ## which was generated
    path*:string

  Log* = object
    ## Holds all data tied to a build log
    path*:string

proc readTwiddlfile(path:string): Twiddlfile =
  result.path = path
  let jsonNode = parseJson(readFile(path))

  result.name = jsonNode["name"].getStr()
  for job in jsonNode["jobs"].items:
    var
      commands:seq[string]
      artifacts:seq[string]

    for command in job["commands"].items:
      commands.add(command.getStr())
    for artifact in job["artifacts"].items:
      artifacts.add(artifact.getStr())

    result.jobs.add(Job(name:job["name"].getStr(), commands:commands, artifacts:artifacts))

proc saveTwiddlfile*(twf:Twiddlfile) = 
  ## Saves the Twiddlfile
  var jsonResult = %* {"name" : twf.name}

  for jobs in twf.jobs:
    jsonResult["jobs"].add( %* {"name" : jobs.name,
      "commands" : jobs.commands,
      "artifacts" : jobs.artifacts} )

  writeFile(twf.path, $jsonResult)

proc readBuildFile(path:string): Build =
  let
    jsonNode = parseJson(readFile(path))
    job = jsonNode["job"]

  result.id = jsonNode["id"].getInt()
  result.comment = jsonNode["comment"].getStr()
  result.status = jsonNode["status"].getStr().parseEnum(bsUnknown)

  result.job.name = job["name"].getStr()
  for command in job["commands"].items:
    result.job.commands.add(command.getStr())
  for artifact in job["artifacts"].items:
    result.job.artifacts.add(artifact.getStr())

  if jsonNode.hasKey("startTime"):
    result.timeStarted = some(jsonNode["startTime"].getStr().parse(timeFmt))
  if jsonNode.hasKey("finishTime"):
    result.timeFinished = some(jsonNode["finishTime"].getStr().parse(timeFmt))

  for log in jsonNode["logs"].items:
    result.logs.add(Log(path:log.getStr()))
  for artifact in jsonNode["artifacts"].items:
    result.artifacts.add(Artifact(path:artifact.getStr()))

proc saveBuildFile*(b:Build) =
  ## Saves the build configuration
  var jsonResult = %* {"id" : b.id,
    "comment" : b.comment,
    "status" : $b.status}

  jsonResult["job"] = %* {"name" : b.job.name,
    "commands" : b.job.commands,
    "artifacts" : b.job.artifacts}

  if b.timeStarted.isSome:
    jsonResult["startTime"] = % b.timeStarted.get.format(timeFmt)
  if b.timeFinished.isSome:
    jsonResult["finishTime"] = % b.timeFinished.get.format(timeFmt)

  jsonResult["logs"] = % b.logs.mapIt(it.path)
  jsonResult["artifacts"] = % b.artifacts.mapIt(it.path)
  writeFile(b.path, $jsonResult)

proc openBuilds(path:string): seq[Build] =
  for kind, file in walkDir(path):
    result.add(readBuildFile(file))

proc openTwiddlEnv*(path:string): TwiddlEnv =
  ## Opens a twiddl environment
  result.path = path
  result.twiddlfile = readTwiddlfile(path / "twiddlfile")
  result.builds = openBuilds(path / ".twiddl" / "builds")