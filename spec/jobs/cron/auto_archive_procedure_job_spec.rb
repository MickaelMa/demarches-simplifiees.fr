RSpec.describe Cron::AutoArchiveProcedureJob, type: :job do
  let!(:procedure) { create(:procedure, :published, :with_instructeur, auto_archive_on: nil) }
  let!(:procedure_hier) { create(:procedure, :published, :with_instructeur, auto_archive_on: 1.day.ago.to_date) }
  let!(:procedure_aujourdhui) { create(:procedure, :published, :with_instructeur, auto_archive_on: Time.zone.today) }
  let!(:procedure_demain) { create(:procedure, :published, :with_instructeur, auto_archive_on: 1.day.from_now.to_date) }
  let!(:job) { Cron::AutoArchiveProcedureJob.new }

  subject { job.perform }

  context "when procedures have no auto_archive_on" do
    before do
      subject
      procedure.reload
    end

    it { expect(procedure.close?).to eq false }
  end

  context "when procedures have auto_archive_on set on yesterday or today" do
    let!(:dossier1) { create(:dossier, procedure: procedure_hier, state: Dossier.states.fetch(:brouillon), archived: false) }
    let!(:dossier2) { create(:dossier, procedure: procedure_hier, state: Dossier.states.fetch(:en_construction), archived: false) }
    let!(:dossier3) { create(:dossier, procedure: procedure_hier, state: Dossier.states.fetch(:en_construction), archived: false) }
    let!(:dossier4) { create(:dossier, procedure: procedure_hier, state: Dossier.states.fetch(:en_construction), archived: false) }
    let!(:dossier5) { create(:dossier, procedure: procedure_hier, state: Dossier.states.fetch(:en_instruction), archived: false) }
    let!(:dossier6) { create(:dossier, procedure: procedure_hier, state: Dossier.states.fetch(:accepte), archived: false) }
    let!(:dossier7) { create(:dossier, procedure: procedure_hier, state: Dossier.states.fetch(:refuse), archived: false) }
    let!(:dossier8) { create(:dossier, procedure: procedure_hier, state: Dossier.states.fetch(:sans_suite), archived: false) }
    let!(:dossier9) { create(:dossier, procedure: procedure_aujourdhui, state: Dossier.states.fetch(:en_construction), archived: false) }
    let(:last_operation) { dossier2.dossier_operation_logs.last }

    before do
      subject

      [dossier1, dossier2, dossier3, dossier4, dossier5, dossier6, dossier7, dossier8, dossier9].each(&:reload)

      procedure_hier.reload
      procedure_aujourdhui.reload
    end

    it {
      expect(dossier1.state).to eq Dossier.states.fetch(:brouillon)
      expect(dossier2.state).to eq Dossier.states.fetch(:en_instruction)
      expect(last_operation.operation).to eq('passer_en_instruction')
      expect(last_operation.automatic_operation?).to be_truthy
      expect(dossier3.state).to eq Dossier.states.fetch(:en_instruction)
      expect(dossier4.state).to eq Dossier.states.fetch(:en_instruction)
      expect(dossier5.state).to eq Dossier.states.fetch(:en_instruction)
      expect(dossier6.state).to eq Dossier.states.fetch(:accepte)
      expect(dossier7.state).to eq Dossier.states.fetch(:refuse)
      expect(dossier8.state).to eq Dossier.states.fetch(:sans_suite)
      expect(dossier9.state).to eq Dossier.states.fetch(:en_instruction)
    }

    it {
      expect(procedure_hier.close?).to eq true
      expect(procedure_aujourdhui.close?).to eq true
    }
  end

  context "when procedures have auto_archive_on set on future" do
    before do
      subject
    end

    it { expect(procedure_demain.close?).to eq false }
  end

  context 'when an error occurs' do
    let!(:buggy_procedure) { create(:procedure, :published, :with_instructeur, auto_archive_on: 1.day.ago.to_date) }

    before do
      error = StandardError.new('nop')
      expect(buggy_procedure).to receive(:close!).and_raise(error)
      expect(job).to receive(:procedures_to_close).and_return([buggy_procedure, procedure_hier])
      expect(Raven).to receive(:capture_exception).with(error, extra: { procedure_id: buggy_procedure.id })

      subject
    end

    it "should close all the procedure" do
      expect(procedure_hier.reload.close?).to eq true
    end
  end
end
