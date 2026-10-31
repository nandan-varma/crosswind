// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Testing

@testable import CrosswindKit

@Suite("AppStream parser")
struct AppStreamParserTests {
    @Test("keeps desktop applications and skips runtimes, addons and console apps")
    func filtersComponentTypes() throws {
        let apps = try CatalogFixtures.sampleApps()
        #expect(apps.map(\.id) == [
            "ai.jan.Jan",
            "org.darktable.Darktable",
            "br.com.eduk.school",
            "ai.lmstudio.lm-studio",
        ])
    }

    @Test("maps darktable metadata")
    func darktableFields() throws {
        let apps = try CatalogFixtures.sampleApps()
        let app = try #require(apps.first { $0.id == "org.darktable.Darktable" })
        #expect(app.name == "darktable")
        #expect(app.summary == "Organize and develop images from digital cameras")
        #expect(app.categories == ["Graphics", "Photography"])
        #expect(app.keywords.contains("raw"))
        #expect(app.developerName == "darktable developers")
        #expect(app.projectLicense == "GPL-3.0+")
        #expect(app.homepage == URL(string: "https://www.darktable.org/"))
        #expect(app.bugtracker?.host == "github.com")
        #expect(app.help != nil)
        #expect(app.donation == nil)
        #expect(!app.isVerified)  // no flathub::verification entry in the feed
        #expect(app.bundle == CatalogBundle(arch: "x86_64", branch: "stable"))
        #expect(app.contentRating.isEmpty)  // <content_rating type="oars-1.1"/> with no attributes
        #expect(app.description.hasPrefix("darktable manages your camera raw files"))
        #expect(app.description.contains("\n\nOther modes besides lighttable"))
    }

    @Test("maps remote icons, screenshots and releases")
    func mediaAndReleases() throws {
        let apps = try CatalogFixtures.sampleApps()
        let app = try #require(apps.first { $0.id == "org.darktable.Darktable" })

        let icon = try #require(app.icons.first { $0.width == 128 && $0.scale == 1 })
        #expect(icon.url.host == "dl.flathub.org")
        #expect(app.icons.allSatisfy { $0.url.scheme == "https" })

        #expect(app.screenshots.count == 2)
        let shot = try #require(app.screenshots.last)
        #expect(shot.isDefault)
        #expect(shot.caption == "Virtual dark room with an opened image")
        let source = try #require(shot.images.first { $0.kind == .source })
        #expect(source.width == 1920 && source.height == 1080)
        #expect(shot.images.contains { $0.kind == .thumbnail && $0.width == 1248 })

        let latest = try #require(app.releases.first)
        #expect(latest.version == "5.6.2")
        #expect(latest.type == "stable")
        #expect(latest.date == Date(timeIntervalSince1970: 1_791_072_000))
    }

    @Test("renders lists as bullets and ignores translated text")
    func jan() throws {
        let apps = try CatalogFixtures.sampleApps()
        let app = try #require(apps.first { $0.id == "ai.jan.Jan" })
        #expect(app.summary == "Private offline AI assistant")
        #expect(app.description.contains("\n\n• Local AI models: Run LLMs such as Llama"))
        #expect(!app.description.contains("Prywatny"))
        #expect(app.isVerified)
    }

    @Test("falls back to the developer name and reports unverified apps")
    func fallbacks() throws {
        let apps = try CatalogFixtures.sampleApps()
        let school = try #require(apps.first { $0.id == "br.com.eduk.school" })
        #expect(school.developerName == "eduK")  // no <developer_name>; taken from <developer><name>
        let lmstudio = try #require(apps.first { $0.id == "ai.lmstudio.lm-studio" })
        #expect(!lmstudio.isVerified)
    }

    @Test("reads OARS ratings, verification and paragraph structure from inline XML")
    func inlineComponent() throws {
        let xml = """
        <components version="0.8" origin="flatpak">
          <component type="desktop-application">
            <id>org.example.Rated</id>
            <name>Rated</name>
            <summary>Summary</summary>
            <summary xml:lang="de">Zusammenfassung</summary>
            <description>
              <p>First <em>emphasised</em> paragraph.</p>
              <ul><li>One</li><li>Two</li></ul>
            </description>
            <content_rating type="oars-1.1">
              <content_attribute id="violence-fantasy">mild</content_attribute>
              <content_attribute id="language-profanity">none</content_attribute>
            </content_rating>
            <custom><value key="flathub::verification::verified">true</value></custom>
            <releases><release version="2.0" timestamp="1700000000" type="stable"/></releases>
          </component>
        </components>
        """
        let app = try #require(AppStreamParser.parse(xml: Data(xml.utf8)).first)
        #expect(app.summary == "Summary")
        #expect(app.description == "First emphasised paragraph.\n\n• One\n\n• Two")
        #expect(app.contentRating == ["violence-fantasy": "mild", "language-profanity": "none"])
        #expect(app.isVerified)
        #expect(app.releases.first?.date == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test("gzip input yields the same catalog as raw XML")
    func gzipMatchesXML() throws {
        let gzipped = try AppStreamParser.parse(gzipped: CatalogFixtures.data("appstream-sample", "xml.gz"))
        #expect(gzipped == (try CatalogFixtures.sampleApps()))
    }

    @Test("rejects data that is not gzip")
    func rejectsNonGzip() {
        #expect(throws: AppStreamError.notGzip) {
            _ = try AppStreamParser.parse(gzipped: Data("not gzip at all".utf8))
        }
    }

    @Test("parses about 4,200 components in well under 3 seconds")
    func benchmark() throws {
        let raw = try CatalogFixtures.data("appstream-sample", "xml")
        let sample = try #require(String(data: raw, encoding: .utf8))
        let open = try #require(sample.range(of: "<components"))
        let bodyStart = try #require(sample[open.upperBound...].range(of: ">")).upperBound
        let bodyEnd = try #require(sample.range(of: "</components>")).lowerBound
        let body = String(sample[bodyStart..<bodyEnd])
        let sampleComponents = 7
        let copies = 4_200 / sampleComponents
        let xml = Data((String(sample[..<bodyStart]) + String(repeating: body, count: copies)
            + String(sample[bodyEnd...])).utf8)

        let clock = ContinuousClock()
        var apps: [CatalogApp] = []
        let elapsed = try clock.measure {
            apps = try AppStreamParser.parse(xml: xml)
        }
        print("AppStream parse: \(copies * sampleComponents) components, \(xml.count / 1_000_000) MB, \(elapsed)")
        #expect(apps.count == copies * 4)
        #expect(elapsed < .seconds(3))
    }
}
