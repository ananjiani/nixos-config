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

	// Author archive listing pages (e.g., /archive/marx/works/index.htm)
	// These list multiple works — look for pages with many links to .htm files
	var infoSpans = doc.querySelectorAll('span.info');
	var title = doc.querySelector('title');

	// Index pages with publication metadata are full "book" records
	if (infoSpans.length > 0) {
		return "book";
	}

	// Chapter/article pages within /archive/ that have an author meta tag
	var authorMeta = doc.querySelector('meta[name="author"], meta[name="AUTHOR"], meta[name="Author"]');
	if (authorMeta && url.match(/\/archive\//i)) {
		return "bookSection";
	}

	// Reference section pages (e.g., /reference/archive/)
	if (authorMeta && url.match(/\/reference\//i)) {
		return "bookSection";
	}

	return false;
}

function doWeb(doc, url) {
	scrape(doc, url);
}

function scrape(doc, url) {
	// Determine item type based on presence of <span class="info"> metadata
	var infoSpans = doc.querySelectorAll('span.info');
	var isIndexPage = infoSpans.length > 0;
	var itemType = isIndexPage ? "book" : "bookSection";

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

	// If this is a bookSection, try to extract the book title from breadcrumb
	// and use the chapter heading as the section title
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
						if (!item.date) {
							item.date = value;
						}
						break;
					case 'first published':
						item.date = value;
						break;
					case 'source':
						// Parse source like "Marx/Engels Selected Works, Vol. One, Progress Publishers, Moscow, 1969, pp. 98-137"
						item.extra = (item.extra ? item.extra + '\n' : '') + 'Source: ' + value;
						// Try to extract publisher and place from source string
						var sourceMatch = value.match(/(.+?),\s*(\d{4})/);
						if (sourceMatch) {
							var sourceParts = sourceMatch[1].split(',');
							if (sourceParts.length >= 2) {
								item.publisher = sourceParts[sourceParts.length - 2].trim();
								item.place = sourceParts[sourceParts.length - 1].trim();
							}
						}
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
	item.libraryCatalog = 'Marxists Internet Archive';

	// --- Abstract from meta description ---
	var descMeta = doc.querySelector('meta[name="description"], meta[name="Description"]');
	if (descMeta) {
		var desc = descMeta.getAttribute('content').trim();
		// Only use as abstract if it's substantive (not just a repeat of the title)
		if (desc.length > 20 && desc !== item.title) {
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
				"libraryCatalog": "Marxists Internet Archive",
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
				"libraryCatalog": "Marxists Internet Archive",
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
				"libraryCatalog": "Marxists Internet Archive",
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
				"libraryCatalog": "Marxists Internet Archive",
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
				"libraryCatalog": "Marxists Internet Archive",
				"url": "https://www.marxists.org/archive/gramsci/prison_notebooks/problems/intellectuals.htm"
			}
		]
	}
]
