#
# Platform stuff
#
User.destroy_all
guest = User.create!(:id => 0, :name => 'Guest')
admin = User.create!(:id => 1, :name => 'Admin')
user  = User.create!(:id => 2, :name => 'User')
dev   = User.create!(:id => 3, :name => 'Developer')

#
# Tr8n stuff
#
Tr8n::Language.destroy_all
en_US = Tr8n::Language.create!(:locale => 'en-US', :english_name => 'English', :native_name => 'English', :enabled => true)
en_PL = Tr8n::Language.create!(:locale => 'en-PL', :english_name => 'Pig Latin', :native_name => 'Igpay Atinlay', :enabled => true, :fallback_language_id =>en_US.id)

Tr8n::Translator.destroy_all
trans = User.create!(:id => 4, :name => 'Translator')
Tr8n::Translator.create!(:name => 'Default Translator', :user => trans)