# frozen_string_literal: true

class DsaClassificationSerializer < ApplicationSerializer
  attributes :statement_ids, :community_rules, :categories

  def statement_ids
    object.select(&:pending?).map(&:id)
  end

  def community_rules
    DsaStatementOfRecord.community_rules.map { |rule| rule.slice("id", "ground") }
  end

  def categories
    DsaStatementOfRecord::CATEGORIES.map do |category|
      { id: category, name: I18n.t("dsa_statements.categories.#{category}") }
    end
  end
end
