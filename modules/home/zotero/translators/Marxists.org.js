{
	"translatorID": "f2e4c3b1-7a8d-4e6f-9b0c-1d2e3f4a5b6c",
	"label": "Marxists.org",
	"creator": "Ammar Nanjiani",
	"target": "^https?://(www\\.)?marxists\\.org/",
	"minVersion": "3.0",
	"maxVersion": "",
	"priority": 100,
	"inRepository": false,
	"translatorType": 4,
	"browserSupport": "gcsibv",
	"lastUpdated": "2026-04-03 00:00:00"
}

/*
	Zotero web translator for Marxists Internet Archive (marxists.org).

	Extracts bibliographic metadata from archive pages including:
	- Author from <meta name="author">
	- Title from <title> tag
	- Date from URL path or <span class="info"> blocks
	- Source/publisher from <span class="info">Source:</span>
	- Translator from <span class="info">Translated:</span>
	- Keywords/tags from <meta name="keywords"> and <meta name="classification">
*/

function detectWeb(doc, url) {
	// Skip the homepage and top-level navigation pages
	if (url.match(/marxists\.org\/?$/)) {
		return false;
	}

	// Letters/correspondence
	if (url.match(/\/letters?\//i)) {
		return "letter";
	}

	// Glossary and encyclopedia entries
	if (url.match(/\/(glossary|encyclopedia)\//i)) {
		return "encyclopediaArticle";
	}

	var infoSpans = doc.querySelectorAll('span.info');
	var authorMeta = doc.querySelector('meta[name="author"], meta[name="AUTHOR"], meta[name="Author"]');

	// Index pages with publication metadata — check if it's a multi-chapter work
	if (infoSpans.length > 0) {
		// Look for links to chapters (ch01.htm, ch02.htm, etc.)
		var chapterLinks = doc.querySelectorAll('a[href*="ch0"], a[href*="ch1"], a[href*="ch2"], a[href*="ch3"]');
		if (chapterLinks.length > 1) {
			return "book";
		}
		// Single-page works with info spans (pamphlets, short essays, speeches)
		return "document";
	}

	// Chapter/article pages within /archive/ that have an author meta tag
	if (authorMeta && url.match(/\/archive\//i)) {
		// Check if this page is a chapter within a larger work (breadcrumb has index link)
		var breadcrumb = doc.querySelector('p.title');
		if (breadcrumb) {
			var indexLink = breadcrumb.querySelector('a[href*="index.htm"]');
			if (indexLink) {
				return "bookSection";
			}
		}
		return "document";
	}

	// Reference section pages
	if (authorMeta && url.match(/\/reference\//i)) {
		return "document";
	}

	return false;
}

function doWeb(doc, url) {
	scrape(doc, url);
}

function parseSource(item, value) {
	// Always preserve the full source string in Extra
	item.extra = (item.extra ? item.extra + '\n' : '') + 'Source: ' + value;

	// Extract volume: "Vol. One", "Vol. I", "Volume 3", etc.
	var volMatch = value.match(/Vol(?:ume)?\.?\s+(\w+)/i);
	if (volMatch) {
		item.volume = volMatch[1];
	}

	// Extract edition: "English Edition of 1871", "2nd Edition", "Fourth Edition", etc.
	var editionMatch = value.match(/(.+?\s+Edition(?:\s+of\s+\d{4})?)/i);
	if (editionMatch) {
		item.edition = editionMatch[1].trim();
		return; // Edition-style sources are simple, don't try to parse further
	}

	// Extract page range: "pp. 98-137" or "p. 42"
	var ppMatch = value.match(/pp?\.\s*([\d\-–]+)/);
	if (ppMatch) {
		item.pages = ppMatch[1];
	}

	// Try to extract publisher, place, and year from structured source strings
	// Pattern: "..., Publisher, Place, Year, ..."
	var pubMatch = value.match(/,\s*([^,]+?),\s*([A-Z][a-z]+(?:\s+[A-Z][a-z]+)?),\s*(\d{4})/);
	if (pubMatch) {
		item.publisher = pubMatch[1].trim();
		item.place = pubMatch[2].trim();
	}

	// Extract series name if in parentheses at the start
	var seriesMatch = value.match(/^\(([^)]+)\)/);
	if (seriesMatch) {
		item.series = seriesMatch[1].trim();
	}
}

function scrape(doc, url) {
	var itemType = detectWeb(doc, url);
	if (!itemType) return;

	var infoSpans = doc.querySelectorAll('span.info');
	var isIndexPage = infoSpans.length > 0;

	var item = new Zotero.Item(itemType);

	// --- Author ---
	var authorMeta = doc.querySelector('meta[name="author"], meta[name="AUTHOR"], meta[name="Author"]');
	if (authorMeta) {
		var authorStr = authorMeta.getAttribute('content');
		// Handle "Karl Marx and Frederick Engels" or "Karl Marx, Frederick Engels"
		var authors = authorStr.split(/\s+and\s+|,\s*/);
		for (var i = 0; i < authors.length; i++) {
			var name = authors[i].trim();
			if (name) {
				item.creators.push(Zotero.Utilities.cleanAuthor(name, "author"));
			}
		}
	}

	// --- Title ---
	var titleEl = doc.querySelector('title');
	if (titleEl) {
		var fullTitle = titleEl.textContent.trim();
		item.title = fullTitle;
	}

	// --- Letter-specific: extract recipient from title ---
	// Titles like "Letters: Marx to J. Weydemeyer in New York"
	if (itemType === "letter" && item.title) {
		var recipientMatch = item.title.match(/\bto\s+(.+?)(?:\s+in\s+.+)?(?:\s*\[|$)/i);
		if (recipientMatch) {
			item.creators.push(Zotero.Utilities.cleanAuthor(recipientMatch[1].trim(), "recipient"));
		}
	}

	// If this is a bookSection, try to extract the book title from breadcrumb
	if (itemType === "bookSection") {
		var breadcrumb = doc.querySelector('p.title');
		if (breadcrumb) {
			// The last link in the breadcrumb before the plain text is usually the work title
			var links = breadcrumb.querySelectorAll('a.title');
			if (links.length > 0) {
				var lastLink = links[links.length - 1];
				// If the last link points to an index page, it's the book title
				if (lastLink.getAttribute('href') && lastLink.getAttribute('href').match(/index\.htm/)) {
					item.bookTitle = lastLink.textContent.trim();
				}
			}
		}
	}

	// --- Publication info from <span class="info"> blocks (index pages) ---
	if (isIndexPage) {
		var infoContainer = doc.querySelector('p.information');
		if (infoContainer) {
			var spans = infoContainer.querySelectorAll('span.info');
			for (var i = 0; i < spans.length; i++) {
				var label = spans[i].textContent.trim().replace(/:$/, '').toLowerCase();
				// Get the text node(s) after the span until the next <br> or <span>
				var valueNode = spans[i].nextSibling;
				var value = '';
				while (valueNode && valueNode.nodeName !== 'BR' && valueNode.nodeName !== 'SPAN') {
					if (valueNode.nodeType === 3) { // text node
						value += valueNode.textContent;
					} else if (valueNode.nodeType === 1) { // element node
						if (valueNode.nodeName === 'A') {
							value += valueNode.textContent;
						} else if (valueNode.nodeName === 'SPAN') {
							break;
						} else {
							value += valueNode.textContent;
						}
					}
					valueNode = valueNode.nextSibling;
				}
				value = value.trim().replace(/[;,]\s*$/, '').trim();

				switch (label) {
					case 'written':
						// Preserve "Written" date in Extra for scholarly context
						if (value) {
							item.extra = (item.extra ? item.extra + '\n' : '') + 'Written: ' + value;
						}
						if (!item.date) {
							item.date = value;
						}
						break;
					case 'first published':
						item.date = value;
						break;
					case 'source':
						parseSource(item, value);
						break;
					case 'translated':
						var translators = value.split(/\s+in cooperation with\s+|,\s*/);
						for (var j = 0; j < translators.length; j++) {
							var tName = translators[j].trim();
							if (tName) {
								item.creators.push(Zotero.Utilities.cleanAuthor(tName, "translator"));
							}
						}
						break;
					case 'transcription/markup':
					case 'transcription/html markup':
						var transcribers = value.split(/\s*[&,]\s*|\s+and\s+|;\s*/);
						for (var j = 0; j < transcribers.length; j++) {
							var trName = transcribers[j].trim();
							if (trName) {
								item.creators.push(Zotero.Utilities.cleanAuthor(trName, "contributor"));
							}
						}
						break;
					case 'proofed':
						// Strip common prefixes: "and corrected by X 2009", "and corrected against ... by X 2004"
						var proofed = value.replace(/^and\s+corrected\s+(?:against\s+.+?\s+)?by\s+/i, '').replace(/\s+\d{4}\.?$/, '').trim();
						if (proofed) {
							var proofers = proofed.split(/\s*[&,]\s*|\s+and\s+|;\s*/);
							for (var j = 0; j < proofers.length; j++) {
								var prName = proofers[j].trim();
								if (prName) {
									item.creators.push(Zotero.Utilities.cleanAuthor(prName, "contributor"));
								}
							}
						}
						break;
				}
			}
		}
	}

	// --- Date fallback: extract from URL ---
	if (!item.date) {
		// Match patterns like /1848/ or /1867-c1/ or /1917/
		var dateMatch = url.match(/\/(\d{4})(?:-[^\/]+)?\/[^\/]+/);
		if (dateMatch) {
			item.date = dateMatch[1];
		}
	}

	// --- Tags from keywords and classification ---
	var keywordsMeta = doc.querySelector('meta[name="keywords"], meta[name="Keywords"], meta[name="KEYWORDS"]');
	if (keywordsMeta) {
		var keywords = keywordsMeta.getAttribute('content').split(',');
		for (var i = 0; i < keywords.length; i++) {
			var kw = keywords[i].trim();
			if (kw) {
				item.tags.push(kw);
			}
		}
	}
	var classificationMeta = doc.querySelector('meta[name="classification"], meta[name="Classification"]');
	if (classificationMeta) {
		var classifications = classificationMeta.getAttribute('content').split(',');
		for (var i = 0; i < classifications.length; i++) {
			var cl = classifications[i].trim();
			if (cl) {
				item.tags.push(cl);
			}
		}
	}

	// --- URL and access date ---
	item.url = url;
	item.accessDate = 'CURRENT_TIMESTAMP';
	item.archive = 'Marxists Internet Archive';

	// --- Abstract from meta description ---
	var descMeta = doc.querySelector('meta[name="description"], meta[name="Description"]');
	if (descMeta) {
		var desc = descMeta.getAttribute('content').trim();
		// Only use as abstract if it's substantive (not just a repeat of the title)
		if (desc.length > 20 && desc !== item.title && !desc.match(/^\*/)) {
			item.abstractNote = desc;
		}
	}

	item.complete();
}

/*
	Test cases
*/
var testCases = [
	{
		"type": "web",
		"url": "https://www.marxists.org/archive/marx/works/1848/communist-manifesto/index.htm",
		"items": [
			{
				"itemType": "book",
				"title": "Manifesto of the Communist Party",
				"creators": [
					{
						"firstName": "Karl",
						"lastName": "Marx",
						"creatorType": "author"
					},
					{
						"firstName": "Frederick",
						"lastName": "Engels",
						"creatorType": "author"
					}
				],
				"date": "February 1848",
				"archive": "Marxists Internet Archive",
				"url": "https://www.marxists.org/archive/marx/works/1848/communist-manifesto/index.htm"
			}
		]
	},
	{
		"type": "web",
		"url": "https://www.marxists.org/archive/marx/works/1867-c1/ch01.htm",
		"items": [
			{
				"itemType": "bookSection",
				"title": "Economic Manuscripts: Capital Vol. I - Chapter One",
				"creators": [
					{
						"firstName": "Karl",
						"lastName": "Marx",
						"creatorType": "author"
					}
				],
				"date": "1867",
				"archive": "Marxists Internet Archive",
				"url": "https://www.marxists.org/archive/marx/works/1867-c1/ch01.htm"
			}
		]
	},
	{
		"type": "web",
		"url": "https://www.marxists.org/archive/lenin/works/1917/staterev/ch01.htm",
		"items": [
			{
				"itemType": "bookSection",
				"title": "The State and Revolution — Chapter 1",
				"creators": [
					{
						"firstName": "Vladimir",
						"lastName": "Lenin",
						"creatorType": "author"
					}
				],
				"date": "1917",
				"archive": "Marxists Internet Archive",
				"url": "https://www.marxists.org/archive/lenin/works/1917/staterev/ch01.htm"
			}
		]
	},
	{
		"type": "web",
		"url": "https://www.marxists.org/archive/luxemburg/1913/accumulation-capital/ch01.htm",
		"items": [
			{
				"itemType": "bookSection",
				"title": "Rosa Luxemburg: The Accumulation of Capital (Chap.1)",
				"creators": [
					{
						"firstName": "Rosa",
						"lastName": "Luxemburg",
						"creatorType": "author"
					}
				],
				"date": "1913",
				"archive": "Marxists Internet Archive",
				"url": "https://www.marxists.org/archive/luxemburg/1913/accumulation-capital/ch01.htm"
			}
		]
	},
	{
		"type": "web",
		"url": "https://www.marxists.org/archive/gramsci/prison_notebooks/problems/intellectuals.htm",
		"items": [
			{
				"itemType": "bookSection",
				"title": "Prison Notebooks of Antonio Gramsci",
				"creators": [
					{
						"firstName": "Antonio",
						"lastName": "Gramsci",
						"creatorType": "author"
					}
				],
				"archive": "Marxists Internet Archive",
				"url": "https://www.marxists.org/archive/gramsci/prison_notebooks/problems/intellectuals.htm"
			}
		]
	}
]
