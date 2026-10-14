# frozen_string_literal: true

RSpec.describe DsaStatementOfRecord::Classify do
  describe described_class::Contract, type: :model do
    it { is_expected.to validate_presence_of(:reviewable_id) }
    it { is_expected.to validate_presence_of(:community_rule) }
    it { is_expected.to validate_presence_of(:statement_ids) }

    it do
      is_expected.to validate_inclusion_of(:category).in_array(DsaStatementOfRecord::CATEGORIES)
    end
  end

  describe ".call" do
    subject(:result) { described_class.call(params:, **dependencies) }

    fab!(:admin)
    fab!(:reviewable, :reviewable_flagged_post)
    fab!(:statement) { Fabricate(:dsa_statement_of_record, reviewable_id: reviewable.id) }

    let(:dependencies) { { guardian: admin.guardian } }
    let(:rule) do
      {
        "ground" => "Terms of Service, section 3: Personal attacks",
        "explanation" => "The content targets another person with insults.",
      }
    end
    let(:params) do
      {
        reviewable_id: reviewable.id,
        community_rule: DsaStatementOfRecord.community_rules.first.fetch("id"),
        category: "STATEMENT_CATEGORY_ILLEGAL_OR_HARMFUL_SPEECH",
        statement_ids: [statement.id],
      }
    end

    before do
      SiteSetting.dsa_reporting_enabled = true
      SiteSetting.dsa_community_rules = [rule].to_json
    end

    it "classifies the pending statements and adds a moderation note" do
      account_statement =
        Fabricate(
          :dsa_statement_of_record,
          reviewable_id: reviewable.id,
          payload: {
            "decision_account" => "DECISION_ACCOUNT_SUSPENDED",
          },
        )
      params[:statement_ids] << account_statement.id
      freeze_time

      expect { result }.to change { reviewable.reviewable_notes.count }.by(1)

      expect(result).to run_successfully
      expect(statement.reload).to have_attributes(
        status: "ready",
        classified_by_id: admin.id,
        classified_at: eq_time(Time.current),
      )
      expect(statement.payload).to include(
        "decision_ground" => "DECISION_GROUND_INCOMPATIBLE_CONTENT",
        "incompatible_content_ground" => rule["ground"],
        "incompatible_content_explanation" => rule["explanation"],
        "category" => "STATEMENT_CATEGORY_ILLEGAL_OR_HARMFUL_SPEECH",
        "decision_facts" => "The content was removed.",
      )
      expect(account_statement.reload).to have_attributes(
        status: "ready",
        classified_by_id: admin.id,
        classified_at: eq_time(Time.current),
      )
      expect(account_statement.payload).to include(
        "decision_ground" => "DECISION_GROUND_INCOMPATIBLE_CONTENT",
        "incompatible_content_ground" => rule["ground"],
        "incompatible_content_explanation" => rule["explanation"],
        "category" => "STATEMENT_CATEGORY_ILLEGAL_OR_HARMFUL_SPEECH",
        "decision_facts" => "The account was suspended.",
      )
      expect(reviewable.reviewable_notes.last).to have_attributes(
        user: admin,
        content: <<~TEXT.chomp,
          Classified this moderation decision for DSA reporting.
          Community rule: Terms of Service, section 3: Personal attacks
          Category: Illegal or harmful speech
        TEXT
      )
    end

    context "when the classification note is invalid" do
      before do
        TranslationOverride.upsert!(
          "en",
          "dsa_statements.classification_note",
          "x" * (ReviewableNote::MAX_CONTENT_LENGTH + 1),
        )
      end

      it "rolls back the classification without adding a note" do
        original_payload = statement.payload

        expect { result }.not_to change { reviewable.reviewable_notes.count }

        expect(result).to fail_with_an_invalid_model(:reviewable_note)
        expect(statement.reload).to be_pending
        expect(statement.payload).to eq(original_payload)
        expect(statement.classified_at).to eq(nil)
      end
    end

    context "when the actor is not staff" do
      fab!(:admin, :user)

      it { is_expected.to fail_a_policy(:staff) }
    end

    context "when dsa_reporting_enabled is disabled" do
      before { SiteSetting.dsa_reporting_enabled = false }

      it { is_expected.to fail_a_policy(:classification_enabled) }
    end

    context "when community rules are empty" do
      before do
        params
        SiteSetting.dsa_community_rules = "[]"
      end

      it { is_expected.to fail_a_policy(:classification_enabled) }
    end

    context "when the category is invalid" do
      before { params[:category] = "anything" }

      it { is_expected.to fail_a_contract }
    end

    context "when the selected rule has changed" do
      before do
        params
        SiteSetting.dsa_community_rules = [
          rule.merge("explanation" => "Updated explanation"),
        ].to_json
      end

      it { is_expected.to fail_to_find_a_model(:community_rule) }
    end

    context "when no pending statements remain" do
      before { statement.update!(status: :ready) }

      it "preserves the saved classification without adding another note" do
        original_payload = statement.payload

        expect { result }.not_to change { reviewable.reviewable_notes.count }

        expect(result).to fail_to_find_a_model(:statements)
        expect(statement.reload.payload).to eq(original_payload)
      end
    end

    context "when another decision adds a statement after the form opened" do
      before { Fabricate(:dsa_statement_of_record, reviewable_id: reviewable.id) }

      it { is_expected.to fail_a_policy(:current_statements) }
    end

    context "when a later statement cannot be classified" do
      before do
        unknown =
          Fabricate(
            :dsa_statement_of_record,
            reviewable_id: reviewable.id,
            payload: {
              decision_account: "UNKNOWN",
            },
          )
        params[:statement_ids] << unknown.id
      end

      it "leaves every statement pending without adding a classification note" do
        expect { result }.not_to change { reviewable.reviewable_notes.count }

        expect(result).to fail_a_policy(:supported_restrictions)
        expect(DsaStatementOfRecord.where(reviewable_id: reviewable.id).ready.count).to eq(0)
        expect(statement.reload.payload).not_to have_key("incompatible_content_ground")
      end
    end
  end
end
