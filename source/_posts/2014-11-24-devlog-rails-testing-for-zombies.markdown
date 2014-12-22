---
layout: post
title: "Devlog: Rails Testing"
date: 2014-11-24 00:21:45 +0000
comments: true
categories: ruby codeschool devlog
---

Completed the [Rails Testing _for zombies_](https://www.codeschool.com/courses/rails-testing-for-zombies) courses on [CodeSchool](http://mbsy.co/8TZ9N) tonight.

I liked it, I always found starting a new rails app always triggered my testing OCD and it was nice to get an insight into the strategies one can take to test a rails app without overdoing it.

{% img /images/badges/rtfz_badge.png %}

The course covers how to unit test and integration test your rails app with fixtures using TestUnit, so you are given a good idea of the tools at your disposal out of the box. As a well as that you are introduced to other popular testing gems which make your life easier such as [Shoulda](https://github.com/thoughtbot/shoulda), [Capybara](https://github.com/jnicklas/capybara) and [FactoryGirl](https://github.com/thoughtbot/factory_girl).  I will touch on each of there briefly to give you a taste of what they are all about...

During the Unit Testing section you are introduced to [Shoulda](https://github.com/thoughtbot/shoulda) gem which is described as an alternative syntax that is easy on the fingers and the eyes.

``` ruby
class UserTest < Test::Unit::TestCase
  should have_many(:posts)
  should_not allow_value("blah").for(:email)
end
```

As the course starts to dig into integration testing you are also introduced to [Capybara](https://github.com/jnicklas/capybara) which provides a interaction based DSL for defining your integration tests that supports [multiple drivers](http://www.rubydoc.info/github/jnicklas/capybara#Drivers). Capybara tests when executing act like a headless browser of sorts giving you more control over the interactions with your site or api, following redirects more naturally for example which is something not handles by vanilla rails integration tests so well.


``` ruby
 describe "the signin process", :type => :feature do
  before :each do
    User.make(:email => 'user@example.com', :password => 'password')
  end

  it "signs me in" do
    visit '/sessions/new'
    within("#session") do
      fill_in 'Email', :with => 'user@example.com'
      fill_in 'Password', :with => 'password'
    end
    click_button 'Sign in'
    expect(page).to have_content 'Success'
  end
end
```
Lastly you are introduced to [FactoryGirl](https://github.com/thoughtbot/factory_girl), which is an alternative to using the built in test fixtures provided by rails out of the box.  

<!-- more -->

There are numerous advantages to using a factories and specifically FactoryGirl instead of the built in rails fixture for your test data. You are provided with granular control over how the test data built and initialized not to mention the ability to create test data dynamically rather than maintaining a complex hand crafted static data set defined in yaml with magic ids providing the only basis for associations.

``` ruby 
# This will guess the User class
FactoryGirl.define do
  factory :user do
    first_name "John"
    last_name  "Doe"
    age 27
    admin false
    association :roles

    # This will use the User class
    factory :admin do
      first_name "Admin"
      last_name  "User"
      admin      true
    end
  end

  factory :foo do
    # some fields
  end
end
```

Using the `Factory` method directly will create an instance of an admin and insert it into the DB. 

Beyond this basic example you are able to create new instances without inserting them into the database using the `build` method on the Factory as well as defining associations between entities as simple as adding `association :foo`.

``` ruby
test 'something to do with an admin' do
  user = Factory(:admin)
  assert user.admin
  association :foo
end
```

Insights into a good test strategy that I took away was to unit test the model and have a full suite of integration tests for everything else, which regards to the rails portion of your application anyway, keep your controllers and views logic free.  

This is the approach that I had taken with a node.js app I have been writing, although I have been hand crafting the test data code I think I will look for something like FactoryGirl maybe [this javcascript port](https://www.npmjs.org/package/factory-girl).

So thats another course completed, and was well worth the time, not a bad way to spend some of your Sunday afternoon. I think I might do the [Try R](https://www.codeschool.com/courses/try-r) course next or some [Ember.js](https://www.codeschool.com/courses/warming-up-with-ember-js) which I can put to use in the near future as I am design a website for my wife to kick start a new business idea we have.
