require "test_helper"

describe "PackageDecorator" do
  it "adds an ending dot to descriptions when appropriate" do
    pkg = Package.new(original_description: "Description").decorate
    pkg.description.must_equal "Description."

    pkg = Package.new(original_description: "Description!").decorate
    pkg.description.must_equal "Description!"
  end

  it "capitalizes descriptions" do
    pkg = Package.new(original_description: "helloWORLD.").decorate
    pkg.description.must_equal "HelloWORLD."
  end

  it "escapes HTML and removes Markdown" do
    input = "> Hello _World_! This is about <Form /> elements and <a>link</a>."
    output = "Hello World! This is about &lt;Form /&gt; elements and &lt;a&gt;link&lt;/a&gt;."
    pkg = Package.new(original_description: input).decorate
    pkg.description.must_equal output

    pkg = Package.new(original_description: "## What is it? - a react render").decorate
    pkg.description.must_equal "What is it? - a react render."
  end

  describe "to_tweet" do
    it "generates a tweet about the package" do
      pkg = Package.new(name: "interpolate-components", repo: "Automattic/interpolate-components")
      pkg.description = " A <module> & mixin to turn \n strings\n into structured **React** components without dangerouslyInsertInnerHTML. " +
        "Cross Platform React Native component. Supports selecting a payment method, adding cards manually and using the camera. " +
        "Notifies your app when the user is idle."

      pkg.decorate.to_tweet.must_equal "interpolate-components: A <module> & mixin to turn strings into structured React " +
        "components without dangerouslyInsertInnerHTML. Cross Platform React Native component. Supports selecting a payment " +
        "method, adding cards manually and using the camera. Notifie… https://js.coach/interpolate-components"
    end

    it "returns nil if there isn't a description" do
      pkg = Package.new(name: "example", repo: "example/example")
      pkg.decorate.to_tweet.must_be_nil
    end
  end
end
