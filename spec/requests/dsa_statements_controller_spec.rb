# frozen_string_literal: true

RSpec.describe DsaStatementsController do
  describe "#classify" do
    fab!(:admin)
    fab!(:moderator)
    fab!(:reviewable, :reviewable_flagged_post)
    fab!(:statement) { Fabricate(:dsa_statement_of_record, reviewable_id: reviewable.id) }

    let(:params) do
      {
        community_rule: DsaStatementOfRecord.community_rules.first.fetch("id"),
        category: "STATEMENT_CATEGORY_ILLEGAL_OR_HARMFUL_SPEECH",
        statement_ids: [statement.id],
      }
    end

    before do
      SiteSetting.dsa_reporting_enabled = true
      SiteSetting.dsa_community_rules = [
        {
          ground: "Terms, section 3",
          explanation: "The content targets another person with insults.",
        },
      ].to_json
    end

    it "requires a signed in staff member" do
      put("/review/#{reviewable.id}/dsa-classification.json", params:)
      expect(response).to have_http_status(:forbidden)

      sign_in(Fabricate(:user))
      put("/review/#{reviewable.id}/dsa-classification.json", params:)
      expect(response).to have_http_status(:forbidden)
    end

    it "allows a full moderator to classify a flagged post they can review" do
      sign_in(moderator)

      put("/review/#{reviewable.id}/dsa-classification.json", params:)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["dsa_classification"]["statement_ids"]).to eq([])
      expect(response.parsed_body["reviewable_notes"].sole).to include(
        "id" => reviewable.reviewable_notes.last.id,
        "content" => <<~TEXT.chomp,
          Classified this moderation decision for DSA reporting.
          Community rule: Terms, section 3
          Category: Illegal or harmful speech
        TEXT
        "user" => include("id" => moderator.id),
      )
    end

    it "rejects a flagged post that is outside the moderator's visible categories" do
      category = Fabricate(:private_category, group: Group[:admins])
      reviewable.update!(category:)
      sign_in(moderator)

      put("/review/#{reviewable.id}/dsa-classification.json", params:)

      expect(response).to have_http_status(:not_found)
      expect(statement.reload).to be_pending
    end

    it "rejects a category moderator even when they can review the flagged post" do
      category_moderator = Fabricate(:user)
      group = Fabricate(:group, users: [category_moderator])
      SiteSetting.enable_category_group_moderation = true
      Fabricate(:category_moderation_group, category: reviewable.category, group:)
      sign_in(category_moderator)

      put("/review/#{reviewable.id}/dsa-classification.json", params:)

      expect(response).to have_http_status(:forbidden)
    end

    it "rejects an unknown community rule" do
      sign_in(admin)
      params[:community_rule] = "unknown"

      put("/review/#{reviewable.id}/dsa-classification.json", params:)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["errors"]).to include(I18n.t("dsa_statements.errors.failed"))
    end

    it "rejects an invalid category" do
      sign_in(admin)
      params[:category] = "unknown"

      put("/review/#{reviewable.id}/dsa-classification.json", params:)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects a second classification of the same statement" do
      sign_in(admin)
      statement.update!(status: :ready)

      put("/review/#{reviewable.id}/dsa-classification.json", params:)

      expect(response).to have_http_status(:conflict)
    end

    it "rejects classification when dsa_reporting_enabled is disabled" do
      sign_in(admin)
      SiteSetting.dsa_reporting_enabled = false

      put("/review/#{reviewable.id}/dsa-classification.json", params:)

      expect(response).to have_http_status(:forbidden)
    end
  end
end
