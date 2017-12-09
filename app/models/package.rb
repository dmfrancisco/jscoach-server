class Package < ActiveRecord::Base
  include Search
  include States
  include NPMRelated
  include GithubRelated
  include AlgoliaSync

  extend FriendlyId

  DESCRIPTION_UNAVAILABLE = "No description available."

  friendly_id :name, use: [:slugged, :finders], slug_column: 'slug'

  has_and_belongs_to_many :collections, uniq: true
  has_and_belongs_to_many :filters, uniq: true
  has_and_belongs_to_many :categories, uniq: true

  # Get packages that have at least one associated collection (done by the `join`)
  # Including the filters seems to force distinct
  scope :with_collections, -> { includes(:collections).joins(:collections).includes(:filters) }

  # Get packages that don't have any of the specified collections or no collections at all
  scope :without_collections, -> (collections) {
    joins("left join collections_packages on id = package_id")
    .where("package_id is ? or collection_id not in (?)", nil, collections.pluck(:id))
  }

  # Get packages that don't have any of the specified categories or no categories at all
  scope :without_categories, -> (categories) {
    joins("left join categories_packages on id = categories_packages.package_id")
    .where("categories_packages.package_id is ? or category_id not in (?)", nil, categories.pluck(:id))
  }

  # Get packages which last version has been marked as deprecated
  scope :deprecated, -> { where("(manifest->'deprecated') is not null") }

  # Packages that are associated to collections
  scope :default, -> { joins(:collections).where("collections.default": true) }

  # Published packages with default collections that haven't been tweeted yet
  scope :tweetable, -> { default.published.where(tweeted: false) }

  # I was not able to create an index with `keywords` being an array because "functions
  # in index expression must be marked IMMUTABLE". Instead store serialized keywords.
  serialize :keywords, Array

  with_options if: Proc.new { |p| p.accepted? or p.published? } do |p|
    p.after_save :assign_collections!
    p.after_save :assign_filters!
    p.after_save :assign_categories!
  end

  before_save :update_total_downloads, if: "downloads_changed?"
  before_save :update_donation_url, if: "readme_changed?"

  # Override the default slug generation
  def normalize_friendly_id(string)
    name.gsub("/", "-")
  end

  def assign_collections!
    self.collections |= Collection.discover(self)
  end

  def assign_filters!
    self.filters |= Filter.discover(self)
  end

  def assign_categories!
    self.categories |= Category.discover(self)
  end

  # Use this method when you want to set `repo` to a value that *comes from NPM directly*
  # NOTE: This method may change both `original_repo` and `repo` properties
  def original_repo=(new_repo)
    # Check if the repository has changed. This may happen if the component's author offered
    # the package name to someone else for a new component. If we have a custom repo,
    # only perform a change if the original changed. This allows us to fix wrong repos.
    write_attribute :repo, nil if self.original_repo != new_repo

    write_attribute :original_repo, new_repo
  end

  # Use this method when you want to set `repo` to a value that *may have been changed*
  # manually or automatically (by following redirects on GitHub)
  # NOTE: This method may change both `original_repo` and `repo` properties
  def repo=(new_repo)
    if new_repo.to_s.downcase == self.original_repo.to_s.downcase
      write_attribute :repo, nil
    else
      write_attribute :repo, new_repo
    end
  end

  # If unavailable, default to `original_repo`
  def repo
    read_attribute(:repo).presence || self.original_repo
  end

  # The real value stored in the database
  def repo!
    read_attribute :repo
  end

  def repo_user
    repo.split("/").first if repo.present?
  end

  def repo_name
    repo.split("/").last if repo.present?
  end

  def original_description=(new_description)
    if read_attribute(:description).present? and self.original_description != new_description
      JsCoach.warn "The #{ name } package, which had a custom description, " +
        "has a new description.\nOld: #{ self.description }\nNew: #{ new_description }"
      write_attribute :description, nil
    end
    write_attribute :original_description, new_description
  end

  def description=(new_description)
    if new_description.to_s == self.original_description.to_s
      write_attribute :description, nil
    else
      write_attribute :description, new_description
    end
  end

  def description
    read_attribute(:description).presence || self.original_description
  end

  # The real value stored in the database
  def description!
    read_attribute :description
  end

  # Make some minor transformations to the description before displaying it
  # If unavailable, default to `original_description` or `github_description`
  def humanized_description
    desc = ApplicationController.helpers.plain_text(description) # Escape HTML and remove Markdown
    desc = github_description if desc.blank? or ["[!", "[](", "===", "```"].any? { |s| desc.include? s }

    if desc.blank?
      return "<em>#{ DESCRIPTION_UNAVAILABLE }</em>".html_safe
    else
      desc = "#{ desc }." if /\w/ =~ desc.last # Add trailing dot
      desc[0] = desc[0].upcase # Capitalize 1st letter
      desc.html_safe
    end
  end

  def github_url
    "https://github.com/#{ repo }"
  end

  def readme_plain_text
    Nokogiri::HTML(readme).text
  end

  def deprecated?
    manifest.present? && manifest["deprecated"].present?
  end

  # Force array and downcase to simplify comparison
  def keywords
    read_attribute(:keywords).to_a.compact.map(&:downcase)
  end

  # Returns either a commonly used license or nil
  def normalized_license
    License.normalize(license, fallback: nil) if license
  end

  def update_metadata
    # Pass `repo` to prevent GitHub service from trying to find it again,
    # in case it is not defined in the package.json
    hash = { name: name, custom_repo: repo }

    npm = NPM::Package.new(hash, fetch: true)
    github = Github::Repository.new(npm, fetch: true)

    assign_npm_attributes(npm)
    assign_github_attributes(github)
    self.last_fetched = Time.now
  end

  private

  def update_total_downloads
    values = downloads.map { |day| day["downloads"] }
    self.total_downloads = values.sum
  end

  def update_donation_url
    self.donation_url = Donation.find_link(readme) if readme.present?
  end
end
