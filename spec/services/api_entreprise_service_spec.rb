describe APIEntrepriseService do
  shared_examples 'schedule fetch of all etablissement params' do
    [
      APIEntreprise::EntrepriseJob, APIEntreprise::AssociationJob, APIEntreprise::ExercicesJob,
      APIEntreprise::EffectifsJob, APIEntreprise::EffectifsAnnuelsJob, APIEntreprise::AttestationSocialeJob,
      APIEntreprise::BilansBdfJob
    ].each do |job|
      it "should enqueue #{job.class.name}" do
        expect { subject }.to have_enqueued_job(job)
      end
    end
  end

  describe '#create_etablissement' do
    before do
      stub_request(:get, /https:\/\/entreprise.api.gouv.fr\/v2\/etablissements\/#{siret}/)
        .to_return(body: etablissements_body, status: etablissements_status)
    end

    let(:siret) { '41816609600051' }
    let(:etablissements_status) { 200 }
    let(:etablissements_body) { File.read('spec/fixtures/files/api_entreprise/etablissements.json') }
    let(:valid_token) { "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c" }
    let(:procedure) { create(:procedure, api_entreprise_token: valid_token) }
    let(:dossier) { create(:dossier, procedure: procedure) }
    let(:subject) { APIEntrepriseService.create_etablissement(dossier, siret, procedure.id) }

    before do
      allow_any_instance_of(APIEntrepriseToken).to receive(:roles).and_return([])
      allow_any_instance_of(APIEntrepriseToken).to receive(:expired?).and_return(false)
    end

    context 'when service is up' do
      it 'should fetch etablissement params' do
        expect(subject[:siret]).to eq(siret)
      end

      it_behaves_like 'schedule fetch of all etablissement params'
    end

    context 'when etablissement api down' do
      let(:etablissements_status) { 504 }
      let(:etablissements_body) { '' }

      it 'should raise APIEntreprise::API::Error::RequestFailed' do
        expect { subject }.to raise_error(APIEntreprise::API::Error::RequestFailed)
      end
    end

    context 'when etablissement not found' do
      let(:etablissements_status) { 404 }
      let(:etablissements_body) { '' }

      it 'should return nil' do
        expect(subject).to be_nil
      end
    end
  end

  describe '#create_etablissement_as_degraded_mode' do
    let(:siret) { '41816609600051' }
    let(:procedure) { create(:procedure) }
    let(:dossier) { create(:dossier, procedure: procedure) }
    let(:user_id) { 12 }

    subject(:etablissement) { APIEntrepriseService.create_etablissement_as_degraded_mode(dossier, siret, user_id) }

    it 'should create an etablissement with minimumal attributes' do
      etablissement = subject

      expect(etablissement.siret).to eq(siret)
      expect(etablissement).to be_as_degraded_mode
    end

    it_behaves_like 'schedule fetch of all etablissement params'
  end

  describe "#api_up?" do
    subject { described_class.api_up? }
    let(:body) { File.read('spec/fixtures/files/api_entreprise/current_status.json') }
    let(:status) { 200 }

    before do
      stub_request(:get, "https://entreprise.api.gouv.fr/watchdoge/dashboard/current_status")
        .to_return(body: body, status: status)
    end

    it "returns true when api etablissement is up" do
      expect(subject).to be_truthy
    end

    context "when api entreprise is down" do
      let(:body) do
        original_body = super()

        json = JSON.parse(original_body)
        # API etablissements is the first listed
        json["results"][0]["code"] = 502

        JSON.generate(json)
      end

      it "returns false" do
        expect(subject).to be_falsy
      end
    end

    context "when api entreprise status is unknown" do
      let(:body) { "" }
      let(:status) { 0 }

      it "returns nil" do
        expect(subject).to be_nil
      end
    end
  end
end
