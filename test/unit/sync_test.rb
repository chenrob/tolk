require 'test_helper'
require 'fileutils'

class SyncTest < ActiveSupport::TestCase
  def setup
    Tolk::Locale.delete_all
    Tolk::Translation.delete_all
    Tolk::Phrase.delete_all

    Tolk::Locale.locales_config_path = RAILS_ROOT + "/test/locales/sync"
    Tolk::Locale.primary_locale_name = 'en'
  end

  def test_flat_hash
    data = {'home' => {'hello' => 'hola', 'sidebar' => {'title' => 'something'}}}
    result = Tolk::Locale.send(:flat_hash, data)

    assert_equal 2, result.keys.size
    assert_equal ['home.hello', 'home.sidebar.title'], result.keys.sort
    assert_equal ['hola', 'something'], result.values.sort
  end

  def test_sync_creates_locale_phrases_translations
    Tolk::Locale.sync!

    # Created by sync!
    primary_locale = Tolk::Locale.find_by_name!(Tolk::Locale.primary_locale_name)

    assert_equal ["Hello World", "Nested Hello Country"], primary_locale.translations.map(&:text).sort
    assert_equal ["hello_world", "nested.hello_country"], Tolk::Phrase.all.map(&:key).sort
  end

  def test_sync_deletes_stale_translations_for_secondary_locales_on_delete_all
    spanish = Tolk::Locale.create!(:name => 'es')

    Tolk::Locale.sync!

    phrase = Tolk::Phrase.all.detect {|p| p.key == 'hello_world'}
    hola = spanish.translations.create!(:text => 'hola', :phrase => phrase)

    # Mimic deleting all the translations
    Tolk::Locale.expects(:read_primary_locale_file).returns({})
    Tolk::Locale.sync!

    assert_equal 0, Tolk::Phrase.count
    assert_equal 0, Tolk::Translation.count

    assert_raises(ActiveRecord::RecordNotFound) { hola.reload }
  end

  def test_sync_deletes_stale_translations_for_secondary_locales_on_delete_some
    spanish = Tolk::Locale.create!(:name => 'es')

    Tolk::Locale.sync!

    phrase = Tolk::Phrase.all.detect {|p| p.key == 'hello_world'}
    hola = spanish.translations.create!(:text => 'hola', :phrase => phrase)

    # Mimic deleting 'hello_world'
    Tolk::Locale.expects(:read_primary_locale_file).returns({'nested.hello_country' => 'Nested Hello World'})
    Tolk::Locale.sync!

    assert_equal 1, Tolk::Phrase.count
    assert_equal 1, Tolk::Translation.count
    assert_equal 0, spanish.translations.count

    assert_raises(ActiveRecord::RecordNotFound) { hola.reload }
  end

  def test_sync_handles_deleted_keys_and_updated_translations
    Tolk::Locale.sync!

    # Mimic deleting 'nested.hello_country' and updating 'hello_world'
    Tolk::Locale.expects(:read_primary_locale_file).returns({"hello_world" => "Hello Super World"})
    Tolk::Locale.sync!

    primary_locale = Tolk::Locale.find_by_name!(Tolk::Locale.primary_locale_name)

    assert_equal ['Hello Super World'], primary_locale.translations.map(&:text)
    assert_equal ['hello_world'], Tolk::Phrase.all.map(&:key).sort
  end

  def test_sync_doesnt_mess_with_existing_translations
    spanish = Tolk::Locale.create!(:name => 'es')

    Tolk::Locale.sync!

    phrase = Tolk::Phrase.all.detect {|p| p.key == 'hello_world'}
    hola = spanish.translations.create!(:text => 'hola', :phrase => phrase)

    # Mimic deleting 'nested.hello_country' and updating 'hello_world'
    Tolk::Locale.expects(:read_primary_locale_file).returns({"hello_world" => "Hello Super World"})
    Tolk::Locale.sync!

    hola.reload
    assert_equal 'hola', hola.text
  end

  def test_dump_all_after_sync
    spanish = Tolk::Locale.create!(:name => 'es')

    Tolk::Locale.sync!

    phrase = Tolk::Phrase.all.detect {|p| p.key == 'hello_world'}
    hola = spanish.translations.create!(:text => 'hola', :phrase => phrase)

    tmpdir = RAILS_ROOT + "/tmp/sync/locales"
    FileUtils.mkdir_p(tmpdir)
    Tolk::Locale.dump_all(tmpdir)

    spanish_file = "#{tmpdir}/es.yml"
    data = YAML::load(IO.read(spanish_file))['es']
    assert_equal ['hello_world'], data.keys
    assert_equal 'hola', data['hello_world']
  ensure
    FileUtils.rm_f(tmpdir)
  end
end