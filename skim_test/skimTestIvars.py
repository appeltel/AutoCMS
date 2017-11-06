import FWCore.ParameterSet.Config as cms
process = cms.Process("HIGHPTSKIM")

process.load('Configuration.StandardSequences.Services_cff')
process.load('FWCore.MessageService.MessageLogger_cfi')
process.load('Configuration.EventContent.EventContentHeavyIons_cff')

import FWCore.ParameterSet.VarParsing as VarParsing

ivars = VarParsing.VarParsing('python')
ivars.inputFiles = '/store/hidata/HIRun2015/HIHardProbes/AOD/PromptReco-v1/000/263/745/00000/4CC806D2-2FBA-E511-B191-02163E014106.root'
ivars.parseArguments()


process.source = cms.Source("PoolSource",
   fileNames = cms.untracked.vstring(
ivars.inputFiles
)
)

# =============== Other Statements =====================
process.maxEvents = cms.untracked.PSet(input = cms.untracked.int32(500))
process.options = cms.untracked.PSet(wantSummary = cms.untracked.bool(False))
process.MessageLogger.cerr.FwkReport.reportEvery = 100

#Trigger Selection
### Comment out for the timing being assuming running on secondary dataset with trigger bit selected already
import HLTrigger.HLTfilters.hltHighLevel_cfi
process.hltHIHighPt = HLTrigger.HLTfilters.hltHighLevel_cfi.hltHighLevel.clone()
process.hltHIHighPt.HLTPaths = ['HLT_HISinglePhoton15_*','HLT_HIPuAK4CaloJet80_*','HLT_HIFullTrack45_*'] # for allphysics
process.hltHIHighPt.andOr = cms.bool(True)
process.hltHIHighPt.throw = cms.bool(False)

process.eventFilter_step = cms.Path( process.hltHIHighPt )

process.output = cms.OutputModule("PoolOutputModule",
    outputCommands = process.RECOEventContent.outputCommands,
    fileName = cms.untracked.string('hiHighPt.root'),
    SelectEvents = cms.untracked.PSet(SelectEvents = cms.vstring('eventFilter_step')),
    dataset = cms.untracked.PSet(
      dataTier = cms.untracked.string('RECO'),
      filterName = cms.untracked.string('hiHighPt'))
)

process.output_step = cms.EndPath(process.output)

process.schedule = cms.Schedule(
    process.eventFilter_step,
    process.output_step
)

