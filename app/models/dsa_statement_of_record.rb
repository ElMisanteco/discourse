# frozen_string_literal: true

class DsaStatementOfRecord < ActiveRecord::Base
  TERRITORIAL_SCOPE = %w[
    AT
    BE
    BG
    CY
    CZ
    DE
    DK
    EE
    ES
    FI
    FR
    GR
    HR
    HU
    IE
    IS
    IT
    LI
    LT
    LU
    LV
    MT
    NL
    NO
    PL
    PT
    RO
    SE
    SI
    SK
  ].freeze

  enum :status, { pending: 0, ready: 1 }

  CATEGORIES =
    %w[
      ANIMAL_WELFARE
      CONSUMER_INFORMATION
      CYBER_VIOLENCE
      CYBER_VIOLENCE_AGAINST_WOMEN
      DATA_PROTECTION_AND_PRIVACY_VIOLATIONS
      ILLEGAL_OR_HARMFUL_SPEECH
      INTELLECTUAL_PROPERTY_INFRINGEMENTS
      NEGATIVE_EFFECTS_ON_CIVIC_DISCOURSE_OR_ELECTIONS
      NOT_SPECIFIED_NOTICE
      OTHER_VIOLATION_TC
      PROTECTION_OF_MINORS
      RISK_FOR_PUBLIC_SECURITY
      SCAMS_AND_FRAUD
      SELF_HARM
      UNSAFE_AND_PROHIBITED_PRODUCTS
      VIOLENCE
    ].map { |category| "STATEMENT_CATEGORY_#{category}" }.freeze

  RESTRICTION_FACTS = {
    "DECISION_VISIBILITY_CONTENT_REMOVED" => "content_removed",
    "DECISION_VISIBILITY_CONTENT_DISABLED" => "content_disabled",
    "DECISION_VISIBILITY_CONTENT_DEMOTED" => "content_demoted",
    "DECISION_VISIBILITY_CONTENT_AGE_RESTRICTED" => "content_age_restricted",
    "DECISION_VISIBILITY_CONTENT_INTERACTION_RESTRICTED" => "content_interaction_restricted",
    "DECISION_VISIBILITY_CONTENT_LABELLED" => "content_labelled",
    "DECISION_VISIBILITY_OTHER" => "content_other",
    "DECISION_ACCOUNT_SUSPENDED" => "account_suspended",
    "DECISION_ACCOUNT_TERMINATED" => "account_terminated",
    "DECISION_PROVISION_PARTIAL_SUSPENSION" => "service_partial_suspension",
    "DECISION_PROVISION_TOTAL_SUSPENSION" => "service_total_suspension",
    "DECISION_PROVISION_PARTIAL_TERMINATION" => "service_partial_termination",
    "DECISION_PROVISION_TOTAL_TERMINATION" => "service_total_termination",
    "DECISION_MONETARY_SUSPENSION" => "monetary_suspension",
    "DECISION_MONETARY_TERMINATION" => "monetary_termination",
    "DECISION_MONETARY_OTHER" => "monetary_other",
  }.freeze
  private_constant :RESTRICTION_FACTS

  class << self
    def community_rules
      JSON
        .parse(SiteSetting.dsa_community_rules)
        .map do |rule|
          rule.merge(
            "id" => Digest::SHA256.hexdigest([rule["ground"], rule["explanation"]].to_json),
          )
        end
    end

    def classification_enabled?
      SiteSetting.dsa_reporting_enabled && community_rules.present?
    end
  end

  def decision_facts
    restrictions =
      payload
        .values_at(
          "decision_visibility",
          "decision_account",
          "decision_provision",
          "decision_monetary",
        )
        .flatten
        .compact
    if restrictions.empty? ||
         restrictions.any? { |restriction| !RESTRICTION_FACTS.key?(restriction) }
      return
    end

    restrictions
      .map do |restriction|
        I18n.t(
          "dsa_statements.facts.#{RESTRICTION_FACTS.fetch(restriction)}",
          locale: SiteSetting.default_locale,
        )
      end
      .join(" ")
  end

  def classify!(community_rule:, category:, classified_by:)
    update!(
      payload:
        payload.merge(
          "decision_ground" => "DECISION_GROUND_INCOMPATIBLE_CONTENT",
          "incompatible_content_ground" => community_rule.fetch("ground"),
          "incompatible_content_explanation" => community_rule.fetch("explanation"),
          "category" => category,
          "decision_facts" => decision_facts,
        ),
      status: :ready,
      classified_by_id: classified_by.id,
      classified_at: Time.current,
    )
  end
end

# == Schema Information
#
# Table name: dsa_statement_of_records
#
#  id               :uuid             not null, primary key
#  classified_at    :datetime
#  payload          :jsonb            not null
#  status           :integer          default("pending"), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  classified_by_id :bigint
#  reviewable_id    :bigint           not null
#
# Indexes
#
#  index_dsa_statement_of_records_on_reviewable_id  (reviewable_id)
#
