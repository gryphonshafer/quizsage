# Translation Integration Details

Integrating multiple translations can sometimes present some interesting
challenges regarding how each translation elected to include or exclude, merge
or split up verse content. What follows are details of such translational
differences, followed by how QuizSage integrates these translations.

## Content Differences

Translations include or exclude verse content in 1 of 4 ways:

- **Included** = Content exists as a standard text
- **Bracketed** = Content exists inline wrapped in brackets or otherwise marked as non-standard
    - A postfixed asterisk indicates the bracketing begins in the prior verse
- **Noted** = Content exists in a footnote
- **Omitted** = Content not included (but omission may be noted)

The following table uses the above definitions to describe how each translation
differs from the others:

<div class="table_horizontal_scroll">
    <table id="content_differences">
        <thead>
            <tr>
                <th>Reference(s)</th>
                <th>AKJV</th>
                <th>AMP</th>
                <th>BSB</th>
                <th>ESV</th>
                <th>HCSB</th>
                <th>KJ21</th>
                <th>KJV</th>
                <th>NKJV</th>
                <th>NASB</th>
                <th>NASB5</th>
                <th>NIV</th>
                <th>NIV84</th>
                <th>NLT</th>
                <th>NRSVA</th>
                <th>RSV</th>
            </tr>
        </thead>
        <tbody>
            <tr>
                <td>Matthew 12:47</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Footnoted</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Bracketed</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Footnoted</td>
            </tr>
            <tr>
                <td>Matthew 17:21, 18:11</td>
                <td>Included</td>
                <td>Bracketed</td>
                <td>Noted</td>
                <td>Noted</td>
                <td>Bracketed</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Noted</td>
                <td>Bracketed</td>
                <td>Omitted</td>
                <td>Omitted</td>
                <td>Noted</td>
                <td>Noted</td>
                <td>Noted</td>
            </tr>
            <tr>
                <td>Matthew 21:44</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Bracketed</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Noted</td>
            </tr>
            <tr>
                <td>Matthew 23:14</td>
                <td>Included</td>
                <td>Bracketed</td>
                <td>Noted</td>
                <td>Noted</td>
                <td>Bracketed</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Noted</td>
                <td>Bracketed</td>
                <td>Omitted</td>
                <td>Omitted</td>
                <td>Noted</td>
                <td>Noted</td>
                <td>Noted</td>
            </tr>
            <tr>
                <td>Mark 7:16</td>
                <td>Included</td>
                <td>Bracketed</td>
                <td>Noted</td>
                <td>Noted</td>
                <td>Bracketed</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Noted</td>
                <td>Bracketed</td>
                <td>Omitted</td>
                <td>Omitted</td>
                <td>Noted</td>
                <td>Noted</td>
                <td>Noted</td>
            </tr>
            <tr>
                <td>Mark 9:44</td>
                <td>Included</td>
                <td>Bracketed</td>
                <td>Noted</td>
                <td>Omitted</td>
                <td>Bracketed</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Omitted</td>
                <td>Bracketed</td>
                <td>Omitted</td>
                <td>Omitted</td>
                <td>Noted</td>
                <td>Omitted</td>
                <td>Omitted</td>
            </tr>
            <tr>
                <td>Mark 9:46</td>
                <td>Included</td>
                <td>Bracketed</td>
                <td>Noted</td>
                <td>Omitted</td>
                <td>Bracketed*</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Omitted</td>
                <td>Bracketed</td>
                <td>Omitted</td>
                <td>Omitted</td>
                <td>Noted</td>
                <td>Omitted</td>
                <td>Omitted</td>
            </tr>
            <tr>
                <td>Mark 11:26</td>
                <td>Included</td>
                <td>Bracketed</td>
                <td>Noted</td>
                <td>Noted</td>
                <td>Bracketed</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Bracketed</td>
                <td>Bracketed</td>
                <td>Omitted</td>
                <td>Omitted</td>
                <td>Noted</td>
                <td>Noted</td>
                <td>Noted</td>
            </tr>
            <tr>
                <td>Mark 15:28</td>
                <td>Included</td>
                <td>Bracketed</td>
                <td>Noted</td>
                <td>Noted</td>
                <td>Bracketed</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Noted</td>
                <td>Bracketed</td>
                <td>Omitted</td>
                <td>Omitted</td>
                <td>Noted</td>
                <td>Noted</td>
                <td>Noted</td>
            </tr>
            <tr>
                <td>Mark 16:9-20</td>
                <td>Included</td>
                <td>Bracketed</td>
                <td>Included</td>
                <td>Bracketed</td>
                <td>Bracketed</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Bracketed</td>
                <td>Bracketed</td>
                <td>Bracketed</td>
                <td>Included</td>
                <td>Included</td>
                <td>Bracketed</td>
                <td>Included</td>
            </tr>
            <tr>
                <td>Luke 17:36</td>
                <td>Included</td>
                <td>Bracketed</td>
                <td>Noted</td>
                <td>Noted</td>
                <td>Bracketed</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Bracketed</td>
                <td>Bracketed</td>
                <td>Omitted</td>
                <td>Omitted</td>
                <td>Noted</td>
                <td>Noted</td>
                <td>Noted</td>
            </tr>
            <tr>
                <td>Luke 22:43-44</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Bracketed</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Bracketed</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Bracketed</td>
                <td>Omitted</td>
            </tr>
            <tr>
                <td>Luke 23:17</td>
                <td>Included</td>
                <td>Bracketed</td>
                <td>Noted</td>
                <td>Noted</td>
                <td>Bracketed</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Bracketed</td>
                <td>Bracketed</td>
                <td>Omitted</td>
                <td>Omitted</td>
                <td>Noted</td>
                <td>Noted</td>
                <td>Noted</td>
            </tr>
            <tr>
                <td>Luke 24:12, 40</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Noted</td>
            </tr>
            <tr>
                <td>John 5:4</td>
                <td>Included</td>
                <td>Bracketed*</td>
                <td>Noted</td>
                <td>Noted</td>
                <td>Bracketed*</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Noted</td>
                <td>Bracketed*</td>
                <td>Noted</td>
                <td>Noted</td>
                <td>Noted</td>
                <td>Noted</td>
                <td>Noted</td>
            </tr>
            <tr>
                <td>John 7:53-8:11</td>
                <td>Included</td>
                <td>Bracketed</td>
                <td>Included</td>
                <td>Bracketed</td>
                <td>Bracketed</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Bracketed</td>
                <td>Bracketed</td>
                <td>Bracketed</td>
                <td>Included</td>
                <td>Included</td>
                <td>Bracketed</td>
                <td>Included</td>
            </tr>
            <tr>
                <td>Acts 8:37</td>
                <td>Included</td>
                <td>Bracketed</td>
                <td>Noted</td>
                <td>Noted</td>
                <td>Bracketed</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Noted</td>
                <td>Bracketed</td>
                <td>Noted</td>
                <td>Noted</td>
                <td>Noted</td>
                <td>Noted</td>
                <td>Noted</td>
            </tr>
            <tr>
                <td>Acts 15:34</td>
                <td>Included</td>
                <td>Bracketed</td>
                <td>Noted</td>
                <td>Noted</td>
                <td>Noted</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Noted</td>
                <td>Bracketed</td>
                <td>Noted</td>
                <td>Noted</td>
                <td>Noted</td>
                <td>Noted</td>
                <td>Noted</td>
            </tr>
            <tr>
                <td>Acts 24:7</td>
                <td>Included</td>
                <td>Bracketed*</td>
                <td>Noted</td>
                <td>Noted</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Noted</td>
                <td>Included</td>
                <td>Noted</td>
                <td>Noted</td>
                <td>Noted</td>
                <td>Noted</td>
                <td>Noted</td>
            </tr>
            <tr>
                <td>Acts 28:29</td>
                <td>Included</td>
                <td>Bracketed</td>
                <td>Noted</td>
                <td>Noted</td>
                <td>Bracketed</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Noted</td>
                <td>Bracketed</td>
                <td>Noted</td>
                <td>Noted</td>
                <td>Noted</td>
                <td>Noted</td>
                <td>Noted</td>
            </tr>
            <tr>
                <td>Romans 16:24</td>
                <td>Included</td>
                <td>Bracketed</td>
                <td>Noted</td>
                <td>Noted</td>
                <td>Bracketed</td>
                <td>Included</td>
                <td>Included</td>
                <td>Included</td>
                <td>Noted</td>
                <td>Bracketed</td>
                <td>Noted</td>
                <td>Noted</td>
                <td>Noted</td>
                <td>Noted</td>
                <td>Noted</td>
            </tr>
        </tbody>
    </table>
</div>

### Additional Differences

- The **KJ21** translation has the following additional verses omitted:
    - *Matthew 16:15*
    - *1 Corinthians 2:16, 11:14, 14:8*
    - *1 Thessalonians 2:13*
    - *Titus 2:14*
- **HCSB** and **NRSVA** merge *2 Corinthians 13:12-13* into a single verse 12 and cause verse 14 to become noted as verse 13
- **NRSVA** and **RSV** invert the content of and then merge *James 1:7-8* (causing verse 8 to be omitted as a reference but not its content)
- *3 John 1:14* is split into 2 verses (14-15) in the following: **AMP, ESV, NASB, NASB5, NLT, NRSVA, RSV**
- *Revelation 12:17* is split into 2 verses (17-18) in the following: **HCSB, NLT, NRSVA**

## QuizSage Integration

QuizSage integrates the translations into its material database as follows:

- In the above differences table, any content not “Included” is excluded.
- In any case where bracketed content begins in the prior verse, the bracketed portion of the prior verse is excluded.
- The **HCSB** and **NRSVA** merge of *2 Corinthians 13:12-13* is split.
- The **NRSVA** and **RSV** invert-merge of *James 1:7-8* is left untouched.
- The *3 John 1:14* split in **AMP, ESV, NASB, NASB5, NLT, NRSVA, and RSV** is merged.
- The *Revelation 12:17* split in **HCSB, NLT, and NRSVA** is merged.

## Verse Content Verification Sources

The following are the sources used for verse content verification:

- [Bible Gateway](https://biblegateway.com)
- [Bible Hub](https://biblehub.com)
- [Bible Portal](https://bibleportal.com)
- [Read BSB](https://readbsb.com)
